// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max, abs} from "./utils/Math.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, PermitParams} from "./utils/Types.sol";
import {safeCallWithMinGas} from "./utils/SafeCallMinGas.sol";

/// @title Governance: Modular Initiative based Governance
contract Governance is Multicall, UserProxyFactory, ReentrancyGuard, IGovernance {
    using SafeERC20 for IERC20;

    uint256 constant MIN_GAS_TO_HOOK = 350_000; /// Replace this to ensure hooks have sufficient gas

    /// @inheritdoc IGovernance
    ILQTYStaking public immutable stakingV1;
    /// @inheritdoc IGovernance
    IERC20 public immutable lqty;
    /// @inheritdoc IGovernance
    IERC20 public immutable bold;
    /// @inheritdoc IGovernance
    uint256 public immutable EPOCH_START;
    /// @inheritdoc IGovernance
    uint256 public immutable EPOCH_DURATION;
    /// @inheritdoc IGovernance
    uint256 public immutable EPOCH_VOTING_CUTOFF;
    /// @inheritdoc IGovernance
    uint256 public immutable MIN_CLAIM;
    /// @inheritdoc IGovernance
    uint256 public immutable MIN_ACCRUAL;
    /// @inheritdoc IGovernance
    uint256 public immutable REGISTRATION_FEE;
    /// @inheritdoc IGovernance
    uint256 public immutable REGISTRATION_THRESHOLD_FACTOR;
    /// @inheritdoc IGovernance
    uint256 public immutable UNREGISTRATION_THRESHOLD_FACTOR;
    /// @inheritdoc IGovernance
    uint256 public immutable REGISTRATION_WARM_UP_PERIOD;
    /// @inheritdoc IGovernance
    uint256 public immutable UNREGISTRATION_AFTER_EPOCHS;
    /// @inheritdoc IGovernance
    uint256 public immutable VOTING_THRESHOLD_FACTOR;

    /// @inheritdoc IGovernance
    uint256 public boldAccrued;

    /// @inheritdoc IGovernance
    VoteSnapshot public votesSnapshot;
    /// @inheritdoc IGovernance
    mapping(address => InitiativeVoteSnapshot) public votesForInitiativeSnapshot;

    /// @inheritdoc IGovernance
    GlobalState public globalState;
    /// @inheritdoc IGovernance
    mapping(address => UserState) public userStates;
    /// @inheritdoc IGovernance
    mapping(address => InitiativeState) public initiativeStates;
    /// @inheritdoc IGovernance
    mapping(address => mapping(address => Allocation)) public lqtyAllocatedByUserToInitiative;
    /// @inheritdoc IGovernance
    mapping(address => uint16) public override registeredInitiatives;

    uint16 constant UNREGISTERED_INITIATIVE = type(uint16).max;

    constructor(
        address _lqty,
        address _lusd,
        address _stakingV1,
        address _bold,
        Configuration memory _config,
        address[] memory _initiatives
    ) UserProxyFactory(_lqty, _lusd, _stakingV1) {
        stakingV1 = ILQTYStaking(_stakingV1);
        lqty = IERC20(_lqty);
        bold = IERC20(_bold);
        require(_config.minClaim <= _config.minAccrual, "Gov: min-claim-gt-min-accrual");
        REGISTRATION_FEE = _config.registrationFee;

        // Registration threshold must be below 100% of votes
        require(_config.registrationThresholdFactor < WAD, "Gov: registration-config");
        REGISTRATION_THRESHOLD_FACTOR = _config.registrationThresholdFactor;

        // Unregistration must be X times above the `votingThreshold`
        require(_config.unregistrationThresholdFactor > WAD, "Gov: unregistration-config");
        UNREGISTRATION_THRESHOLD_FACTOR = _config.unregistrationThresholdFactor;

        REGISTRATION_WARM_UP_PERIOD = _config.registrationWarmUpPeriod;
        UNREGISTRATION_AFTER_EPOCHS = _config.unregistrationAfterEpochs;

        // Voting threshold must be below 100% of votes
        require(_config.votingThresholdFactor < WAD, "Gov: voting-config");
        VOTING_THRESHOLD_FACTOR = _config.votingThresholdFactor;

        MIN_CLAIM = _config.minClaim;
        MIN_ACCRUAL = _config.minAccrual;
        EPOCH_START = _config.epochStart;
        require(_config.epochDuration > 0, "Gov: epoch-duration-zero");
        EPOCH_DURATION = _config.epochDuration;
        require(_config.epochVotingCutoff < _config.epochDuration, "Gov: epoch-voting-cutoff-gt-epoch-duration");
        EPOCH_VOTING_CUTOFF = _config.epochVotingCutoff;
        for (uint256 i = 0; i < _initiatives.length; i++) {
            initiativeStates[_initiatives[i]] = InitiativeState(0, 0, 0, 0, 0);
            registeredInitiatives[_initiatives[i]] = 1;
        }
    }

    function _averageAge(uint32 _currentTimestamp, uint32 _averageTimestamp) internal pure returns (uint32) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function _calculateAverageTimestamp(
        uint32 _prevOuterAverageTimestamp,
        uint32 _newInnerAverageTimestamp,
        uint88 _prevLQTYBalance,
        uint88 _newLQTYBalance
    ) internal view returns (uint32) {
        if (_newLQTYBalance == 0) return 0;

        uint32 prevOuterAverageAge = _averageAge(uint32(block.timestamp), _prevOuterAverageTimestamp);
        uint32 newInnerAverageAge = _averageAge(uint32(block.timestamp), _newInnerAverageTimestamp);

        uint88 newOuterAverageAge;
        if (_prevLQTYBalance <= _newLQTYBalance) {
            uint88 deltaLQTY = _newLQTYBalance - _prevLQTYBalance;
            uint240 prevVotes = uint240(_prevLQTYBalance) * uint240(prevOuterAverageAge);
            uint240 newVotes = uint240(deltaLQTY) * uint240(newInnerAverageAge);
            uint240 votes = prevVotes + newVotes;
            newOuterAverageAge = uint32(votes / uint240(_newLQTYBalance));
        } else {
            uint88 deltaLQTY = _prevLQTYBalance - _newLQTYBalance;
            uint240 prevVotes = uint240(_prevLQTYBalance) * uint240(prevOuterAverageAge);
            uint240 newVotes = uint240(deltaLQTY) * uint240(newInnerAverageAge);
            uint240 votes = (prevVotes >= newVotes) ? prevVotes - newVotes : 0;
            newOuterAverageAge = uint32(votes / uint240(_newLQTYBalance));
        }

        if (newOuterAverageAge > block.timestamp) return 0;
        return uint32(block.timestamp - newOuterAverageAge);
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint88 _lqtyAmount) private returns (UserProxy) {
        require(_lqtyAmount > 0, "Governance: zero-lqty-amount");

        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy userProxy = UserProxy(payable(userProxyAddress));

        uint88 lqtyStaked = uint88(stakingV1.stakes(userProxyAddress));

        // update the average staked timestamp for LQTY staked by the user
        UserState memory userState = userStates[msg.sender];
        userState.averageStakingTimestamp = _calculateAverageTimestamp(
            userState.averageStakingTimestamp, uint32(block.timestamp), lqtyStaked, lqtyStaked + _lqtyAmount
        );
        userStates[msg.sender] = userState;

        emit DepositLQTY(msg.sender, _lqtyAmount);

        return userProxy;
    }

    /// @inheritdoc IGovernance
    function depositLQTY(uint88 _lqtyAmount) external nonReentrant {
        UserProxy userProxy = _deposit(_lqtyAmount);
        userProxy.stake(_lqtyAmount, msg.sender);
    }

    /// @inheritdoc IGovernance
    function depositLQTYViaPermit(uint88 _lqtyAmount, PermitParams calldata _permitParams) external nonReentrant {
        UserProxy userProxy = _deposit(_lqtyAmount);
        userProxy.stakeViaPermit(_lqtyAmount, msg.sender, _permitParams);
    }

    /// @inheritdoc IGovernance
    function withdrawLQTY(uint88 _lqtyAmount) external nonReentrant {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        require(address(userProxy).code.length != 0, "Governance: user-proxy-not-deployed");

        uint88 lqtyStaked = uint88(stakingV1.stakes(address(userProxy)));

        UserState storage userState = userStates[msg.sender];

        // check if user has enough unallocated lqty
        require(_lqtyAmount <= lqtyStaked - userState.allocatedLQTY, "Governance: insufficient-unallocated-lqty");

        (uint256 accruedLUSD, uint256 accruedETH) = userProxy.unstake(_lqtyAmount, msg.sender);

        emit WithdrawLQTY(msg.sender, _lqtyAmount, accruedLUSD, accruedETH);
    }

    /// @inheritdoc IGovernance
    function claimFromStakingV1(address _rewardRecipient) external returns (uint256 accruedLUSD, uint256 accruedETH) {
        address payable userProxyAddress = payable(deriveUserProxyAddress(msg.sender));
        require(userProxyAddress.code.length != 0, "Governance: user-proxy-not-deployed");
        return UserProxy(userProxyAddress).unstake(0, _rewardRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernance
    function epoch() public view returns (uint16) {
        if (block.timestamp < EPOCH_START) return 0;
        return uint16(((block.timestamp - EPOCH_START) / EPOCH_DURATION) + 1);
    }

    /// @inheritdoc IGovernance
    function epochStart() public view returns (uint32) {
        uint16 currentEpoch = epoch();
        if (currentEpoch == 0) return 0;
        return uint32(EPOCH_START + (currentEpoch - 1) * EPOCH_DURATION);
    }

    /// @inheritdoc IGovernance
    function secondsWithinEpoch() public view returns (uint32) {
        if (block.timestamp < EPOCH_START) return 0;
        return uint32((block.timestamp - EPOCH_START) % EPOCH_DURATION);
    }

    /// @inheritdoc IGovernance
    function lqtyToVotes(uint88 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp)
        public
        pure
        returns (uint240)
    {
        return uint240(_lqtyAmount) * _averageAge(uint32(_currentTimestamp), _averageTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                 SNAPSHOTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernance
    function getLatestVotingThreshold() public view returns (uint256) {
        uint256 snapshotVotes = votesSnapshot.votes; /// @audit technically can be out of synch

        return calculateVotingThreshold(snapshotVotes);
    }

    function calculateVotingThreshold() public returns (uint256) {
        (VoteSnapshot memory snapshot, ) = _snapshotVotes();

        return calculateVotingThreshold(snapshot.votes);
    }

    function calculateVotingThreshold(uint256 snapshotVotes) public view returns (uint256) {
        if (snapshotVotes == 0) return 0;

        uint256 minVotes; // to reach MIN_CLAIM: snapshotVotes * MIN_CLAIM / boldAccrued
        uint256 payoutPerVote = boldAccrued * WAD / snapshotVotes;
        if (payoutPerVote != 0) {
            minVotes = MIN_CLAIM * WAD / payoutPerVote;
        }
        return max(snapshotVotes * VOTING_THRESHOLD_FACTOR / WAD, minVotes);
    }

    // Snapshots votes for the previous epoch and accrues funds for the current epoch
    function _snapshotVotes() internal returns (VoteSnapshot memory snapshot, GlobalState memory state) {
        bool shouldUpdate;
        (snapshot, state, shouldUpdate) = getTotalVotesAndState();

        if(shouldUpdate) {
            votesSnapshot = snapshot;
            uint256 boldBalance = bold.balanceOf(address(this));
            boldAccrued = (boldBalance < MIN_ACCRUAL) ? 0 : boldBalance;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch);
        }
    }

    function getTotalVotesAndState() public view returns (VoteSnapshot memory snapshot, GlobalState memory state, bool shouldUpdate) {
        uint16 currentEpoch = epoch();
        snapshot = votesSnapshot;
        state = globalState;
        
        if (snapshot.forEpoch < currentEpoch - 1) {
            shouldUpdate = true;

            snapshot.votes = lqtyToVotes(state.countedVoteLQTY, epochStart(), state.countedVoteLQTYAverageTimestamp);
            snapshot.forEpoch = currentEpoch - 1;
        }
    }

    // Snapshots votes for an initiative for the previous epoch but only count the votes
    // if the received votes meet the voting threshold
    function _snapshotVotesForInitiative(address _initiative)
        internal
        returns (InitiativeVoteSnapshot memory initiativeSnapshot, InitiativeState memory initiativeState)
    {
        bool shouldUpdate;
        (initiativeSnapshot, initiativeState, shouldUpdate) = getInitiativeSnapshotAndState(_initiative);

        if(shouldUpdate) {
            votesForInitiativeSnapshot[_initiative] = initiativeSnapshot;
            emit SnapshotVotesForInitiative(_initiative, initiativeSnapshot.votes, initiativeSnapshot.forEpoch);
        }
    }

    function getInitiativeSnapshotAndState(address _initiative)
        public
        view
        returns (InitiativeVoteSnapshot memory initiativeSnapshot, InitiativeState memory initiativeState, bool shouldUpdate)
    {
        // Get the storage data
        uint16 currentEpoch = epoch();
        initiativeSnapshot = votesForInitiativeSnapshot[_initiative];
        initiativeState = initiativeStates[_initiative];

        if (initiativeSnapshot.forEpoch < currentEpoch - 1) {
            shouldUpdate = true;

            uint32 start = epochStart();
            uint240 votes =
                lqtyToVotes(initiativeState.voteLQTY, start, initiativeState.averageStakingTimestampVoteLQTY);
            uint240 vetos =
                lqtyToVotes(initiativeState.vetoLQTY, start, initiativeState.averageStakingTimestampVetoLQTY);
            initiativeSnapshot.votes = uint224(votes);
            initiativeSnapshot.vetos = uint224(vetos);

            initiativeSnapshot.forEpoch = currentEpoch - 1; 
        }
    }

    /// @inheritdoc IGovernance
    function snapshotVotesForInitiative(address _initiative)
        external
        nonReentrant
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot)
    {
        (voteSnapshot,) = _snapshotVotes();
        (initiativeVoteSnapshot,) = _snapshotVotesForInitiative(_initiative);
    }

    /*//////////////////////////////////////////////////////////////
                                 FSM
    //////////////////////////////////////////////////////////////*/


    /// @notice Given an initiative, return whether the initiative will be unregisted, whether it can claim and which epoch it last claimed at
    enum InitiativeStatus {
        NONEXISTENT, /// This Initiative Doesn't exist | This is never returned
        COOLDOWN, /// This epoch was just registered
        SKIP, /// This epoch will result in no rewards and no unregistering
        CLAIMABLE, /// This epoch will result in claiming rewards
        CLAIMED, /// The rewards for this epoch have been claimed
        UNREGISTERABLE, /// Can be unregistered
        DISABLED // It was already Unregistered
    }
    /**
        FSM:
            - Can claim (false, true, epoch - 1 - X)
            - Has claimed (false, false, epoch - 1)
            - Cannot claim and should not be kicked (false, false, epoch - 1 - [0, X])
            - Should be kicked (true, false, epoch - 1 - [UNREGISTRATION_AFTER_EPOCHS, UNREGISTRATION_AFTER_EPOCHS + X])
     */

     function getInitiativeState(address _initiative) public returns (InitiativeStatus status, uint16 lastEpochClaim, uint256 claimableAmount) {
        (VoteSnapshot memory votesSnapshot_,) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) = _snapshotVotesForInitiative(_initiative);

        return getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);
    }

    /// @dev Given an initiative address and its snapshot, determines the current state for an initiative
    function getInitiativeState(address _initiative, VoteSnapshot memory votesSnapshot_, InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) public view returns (InitiativeStatus status, uint16 lastEpochClaim, uint256 claimableAmount) {

        // == Non existent Condition == //
        if(registeredInitiatives[_initiative] == 0) {
            return (InitiativeStatus.NONEXISTENT, 0, 0); /// By definition it has zero rewards
        }

        // == Just Registered Condition == //
        // If a initiative is disabled, we return false and the last epoch claim
        if(registeredInitiatives[_initiative] == epoch()) {
            return (InitiativeStatus.COOLDOWN, 0, 0); /// Was registered this week, cannot have rewards
        }

        // Fetch last epoch at which we claimed
        lastEpochClaim = initiativeStates[_initiative].lastEpochClaim;

        // == Disabled Condition == //
        if(registeredInitiatives[_initiative] == UNREGISTERED_INITIATIVE) {
            return (InitiativeStatus.DISABLED, lastEpochClaim, 0); /// By definition it has zero rewards
        }

        // == Already Claimed Condition == //
        if(lastEpochClaim >= epoch() - 1) {
            // early return, we have already claimed
            return (InitiativeStatus.CLAIMED, lastEpochClaim, claimableAmount);
        }


        // NOTE: Pass the snapshot value so we get accurate result
        uint256 votingTheshold = calculateVotingThreshold(votesSnapshot_.votes);

        // If it's voted and can get rewards
        // Votes > calculateVotingThreshold
        // == Rewards Conditions (votes can be zero, logic is the same) == //

        // By definition if votesForInitiativeSnapshot_.votes > 0 then votesSnapshot_.votes > 0
        if(votesForInitiativeSnapshot_.votes > votingTheshold && !(votesForInitiativeSnapshot_.vetos >= votesForInitiativeSnapshot_.votes)) {
            uint256 claim = votesForInitiativeSnapshot_.votes * boldAccrued / votesSnapshot_.votes;
            return (InitiativeStatus.CLAIMABLE, lastEpochClaim, claim);
        }


        // == Unregister Condition == //
        /// @audit epoch() - 1 because we can have Now - 1 and that's not a removal case | TODO: Double check | Worst case QA, off by one epoch
        /// This shifts the logic by 1 epoch
        if((initiativeState.lastEpochClaim + UNREGISTRATION_AFTER_EPOCHS < epoch() - 1)
            ||  votesForInitiativeSnapshot_.vetos > votesForInitiativeSnapshot_.votes
                        && votesForInitiativeSnapshot_.vetos > votingTheshold * UNREGISTRATION_THRESHOLD_FACTOR / WAD
        ) {
            return (InitiativeStatus.UNREGISTERABLE, lastEpochClaim, 0);
        }
        
        // == Not meeting threshold Condition == //
        return (InitiativeStatus.SKIP, lastEpochClaim, 0);
    }

    /// @inheritdoc IGovernance
    function registerInitiative(address _initiative) external nonReentrant {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);

        require(_initiative != address(0), "Governance: zero-address");
        (InitiativeStatus status, ,) = getInitiativeState(_initiative);
        require(status == InitiativeStatus.NONEXISTENT, "Governance: initiative-already-registered");

        address userProxyAddress = deriveUserProxyAddress(msg.sender);
        (VoteSnapshot memory snapshot,) = _snapshotVotes();
        UserState memory userState = userStates[msg.sender];

        // an initiative can be registered if the registrant has more voting power (LQTY * age)
        // than the registration threshold derived from the previous epoch's total global votes
        require(
            lqtyToVotes(uint88(stakingV1.stakes(userProxyAddress)), block.timestamp, userState.averageStakingTimestamp)
                >= snapshot.votes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-lqty"
        );

        uint16 currentEpoch = epoch();

        registeredInitiatives[_initiative] = currentEpoch;

        emit RegisterInitiative(_initiative, msg.sender, currentEpoch);

        // Replaces try / catch | Enforces sufficient gas is passed
        safeCallWithMinGas(_initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onRegisterInitiative, (currentEpoch)));
    }

    /// @inheritdoc IGovernance
    function allocateLQTY(
        address[] calldata _initiatives,
        int88[] calldata _deltaLQTYVotes,
        int88[] calldata _deltaLQTYVetos
    ) external nonReentrant {
        require(
            _initiatives.length == _deltaLQTYVotes.length && _initiatives.length == _deltaLQTYVetos.length,
            "Governance: array-length-mismatch"
        );

        (VoteSnapshot memory votesSnapshot_ , GlobalState memory state) = _snapshotVotes();

        uint16 currentEpoch = epoch();

        UserState memory userState = userStates[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            int88 deltaLQTYVotes = _deltaLQTYVotes[i];
            int88 deltaLQTYVetos = _deltaLQTYVetos[i];

            // only allow vetoing post the voting cutoff
            require(
                deltaLQTYVotes <= 0 || deltaLQTYVotes >= 0 && secondsWithinEpoch() <= EPOCH_VOTING_CUTOFF,
                "Governance: epoch-voting-cutoff"
            );
            
            /// === Check FSM === ///
            // Can vote positively in SKIP, CLAIMABLE, CLAIMED and UNREGISTERABLE states
            // Force to remove votes if disabled
            // Can remove votes and vetos in every stage
            (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
                _snapshotVotesForInitiative(initiative);

            (InitiativeStatus status, , ) = getInitiativeState(initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);

            if(deltaLQTYVotes > 0 || deltaLQTYVetos > 0) {
                /// @audit FSM CHECK, note that the original version allowed voting on `Unregisterable` Initiatives - Prob should fix
                require(status == InitiativeStatus.SKIP || status == InitiativeStatus.CLAIMABLE || status == InitiativeStatus.CLAIMED  || status == InitiativeStatus.UNREGISTERABLE, "Governance: active-vote-fsm");
            }
            
            if(status == InitiativeStatus.DISABLED) {
                require(deltaLQTYVotes <= 0 && deltaLQTYVetos <= 0, "Must be a withdrawal");
            }

            /// === UPDATE ACCOUNTING === ///
            // == INITIATIVE STATE == //

            // deep copy of the initiative's state before the allocation
            InitiativeState memory prevInitiativeState = InitiativeState(
                initiativeState.voteLQTY,
                initiativeState.vetoLQTY,
                initiativeState.averageStakingTimestampVoteLQTY,
                initiativeState.averageStakingTimestampVetoLQTY,
                initiativeState.lastEpochClaim
            );

            // update the average staking timestamp for the initiative based on the user's average staking timestamp
            initiativeState.averageStakingTimestampVoteLQTY = _calculateAverageTimestamp(
                initiativeState.averageStakingTimestampVoteLQTY,
                userState.averageStakingTimestamp,
                initiativeState.voteLQTY,
                add(initiativeState.voteLQTY, deltaLQTYVotes)
            );
            initiativeState.averageStakingTimestampVetoLQTY = _calculateAverageTimestamp(
                initiativeState.averageStakingTimestampVetoLQTY,
                userState.averageStakingTimestamp,
                initiativeState.vetoLQTY,
                add(initiativeState.vetoLQTY, deltaLQTYVetos)
            );

            // allocate the voting and vetoing LQTY to the initiative
            initiativeState.voteLQTY = add(initiativeState.voteLQTY, deltaLQTYVotes);
            initiativeState.vetoLQTY = add(initiativeState.vetoLQTY, deltaLQTYVetos);

            // update the initiative's state
            initiativeStates[initiative] = initiativeState;


            // == GLOBAL STATE == //

            // update the average staking timestamp for all counted voting LQTY
            /// Discount previous only if the initiative was not unregistered

            /// @audit
            if(status != InitiativeStatus.DISABLED) {
                state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    state.countedVoteLQTYAverageTimestamp,
                    prevInitiativeState.averageStakingTimestampVoteLQTY, /// @audit TODO Write tests that fail from this bug
                    state.countedVoteLQTY,
                    state.countedVoteLQTY - prevInitiativeState.voteLQTY
                );
                state.countedVoteLQTY -= prevInitiativeState.voteLQTY; /// @audit Overflow here MUST never happen2
            }
            /// @audit We cannot add on disabled so the change below is safe
            // TODO More asserts? | Most likely need to assert strictly less voteLQTY here

            /// Add current
            state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                state.countedVoteLQTYAverageTimestamp,
                initiativeState.averageStakingTimestampVoteLQTY,
                state.countedVoteLQTY,
                state.countedVoteLQTY + initiativeState.voteLQTY
            );
            state.countedVoteLQTY += initiativeState.voteLQTY;

            // == USER ALLOCATION == //

            // allocate the voting and vetoing LQTY to the initiative
            Allocation memory allocation = lqtyAllocatedByUserToInitiative[msg.sender][initiative];
            allocation.voteLQTY = add(allocation.voteLQTY, deltaLQTYVotes);
            allocation.vetoLQTY = add(allocation.vetoLQTY, deltaLQTYVetos);
            allocation.atEpoch = currentEpoch;
            require(!(allocation.voteLQTY != 0 && allocation.vetoLQTY != 0), "Governance: vote-and-veto");
            lqtyAllocatedByUserToInitiative[msg.sender][initiative] = allocation;

            // == USER STATE == //
            
            userState.allocatedLQTY = add(userState.allocatedLQTY, deltaLQTYVotes + deltaLQTYVetos);

            emit AllocateLQTY(msg.sender, initiative, deltaLQTYVotes, deltaLQTYVetos, currentEpoch);

            // Replaces try / catch | Enforces sufficient gas is passed
            safeCallWithMinGas(initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onAfterAllocateLQTY, (currentEpoch, msg.sender, userState, allocation, initiativeState)));
        }

        require(
            userState.allocatedLQTY == 0
                || userState.allocatedLQTY <= uint88(stakingV1.stakes(deriveUserProxyAddress(msg.sender))),
            "Governance: insufficient-or-allocated-lqty"
        );

        globalState = state;
        userStates[msg.sender] = userState;
    }

    /// @inheritdoc IGovernance
    function unregisterInitiative(address _initiative) external nonReentrant {
        /// Enforce FSM
        (VoteSnapshot memory votesSnapshot_ , GlobalState memory state) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        (InitiativeStatus status, , ) = getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);
        require(status != InitiativeStatus.NONEXISTENT, "Governance: initiative-not-registered");
        require(status != InitiativeStatus.COOLDOWN, "Governance: initiative-in-warm-up");
        require(status == InitiativeStatus.UNREGISTERABLE, "Governance: cannot-unregister-initiative");

        // Remove weight from current state
        uint16 currentEpoch = epoch();

        /// @audit Invariant: Must only claim once or unregister
        assert(initiativeState.lastEpochClaim < currentEpoch - 1);

        // recalculate the average staking timestamp for all counted voting LQTY if the initiative was counted in
        /// @audit Trophy: `test_property_sum_of_lqty_global_user_matches_0`
        // Removing votes from state desynchs the state until all users remove their votes from the initiative

        state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
            state.countedVoteLQTYAverageTimestamp,
            initiativeState.averageStakingTimestampVoteLQTY,
            state.countedVoteLQTY,
            state.countedVoteLQTY - initiativeState.voteLQTY
        );
        state.countedVoteLQTY -= initiativeState.voteLQTY;
        
        globalState = state;

        /// weeks * 2^16 > u32 so the contract will stop working before this is an issue
        registeredInitiatives[_initiative] = UNREGISTERED_INITIATIVE; 

        emit UnregisterInitiative(_initiative, currentEpoch);

        // Replaces try / catch | Enforces sufficient gas is passed
        safeCallWithMinGas(_initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onUnregisterInitiative, (currentEpoch)));
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external nonReentrant returns (uint256) {
        (VoteSnapshot memory votesSnapshot_ , GlobalState memory state) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        (InitiativeStatus status, , uint256 claimableAmount) = getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);

        if(status != InitiativeStatus.CLAIMABLE) {
            return 0;
        }
        
        /// @audit INVARIANT: You can only claim for previous epoch
        assert(votesSnapshot_.forEpoch == epoch() - 1); 

        /// All unclaimed rewards are always recycled
        /// Invariant `lastEpochClaim` is < epoch() - 1; | 
        /// If `lastEpochClaim` is older than epoch() - 1 it means the initiative couldn't claim any rewards this epoch
        initiativeStates[_initiative].lastEpochClaim = epoch() - 1;

        bold.safeTransfer(_initiative, claimableAmount);

        emit ClaimForInitiative(_initiative, claimableAmount, votesSnapshot_.forEpoch);


        // Replaces try / catch | Enforces sufficient gas is passed
        safeCallWithMinGas(_initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onClaimForInitiative, (votesSnapshot_.forEpoch, claimableAmount)));

        return claimableAmount;
    }
}
