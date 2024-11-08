// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max} from "./utils/Math.sol";
import {_requireNoDuplicates} from "./utils/UniqueArray.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, PermitParams} from "./utils/Types.sol";
import {safeCallWithMinGas} from "./utils/SafeCallMinGas.sol";
import {Ownable} from "./utils/Ownable.sol";

/// @title Governance: Modular Initiative based Governance
contract Governance is Multicall, UserProxyFactory, ReentrancyGuard, Ownable, IGovernance {
    using SafeERC20 for IERC20;

    uint256 constant MIN_GAS_TO_HOOK = 350_000;

    /// Replace this to ensure hooks have sufficient gas

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
        address _owner,
        address[] memory _initiatives
    ) UserProxyFactory(_lqty, _lusd, _stakingV1) Ownable(_owner) {
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

        if (_initiatives.length > 0) {
            registerInitialInitiatives(_initiatives);
        }
    }

    function registerInitialInitiatives(address[] memory _initiatives) public onlyOwner {
        uint16 currentEpoch = epoch();

        for (uint256 i = 0; i < _initiatives.length; i++) {
            initiativeStates[_initiatives[i]] = InitiativeState(0, 0, 0, 0, 0);
            registeredInitiatives[_initiatives[i]] = currentEpoch;

            emit RegisterInitiative(_initiatives[i], msg.sender, currentEpoch);
        }

        _renounceOwnership();
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
        if (block.timestamp < EPOCH_START) {
            return 0;
        }
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
        uint256 snapshotVotes = votesSnapshot.votes;
        /// @audit technically can be out of synch

        return calculateVotingThreshold(snapshotVotes);
    }

    /// @dev Returns the most up to date voting threshold
    /// In contrast to `getLatestVotingThreshold` this function updates the snapshot
    /// This ensures that the value returned is always the latest
    function calculateVotingThreshold() public returns (uint256) {
        (VoteSnapshot memory snapshot,) = _snapshotVotes();

        return calculateVotingThreshold(snapshot.votes);
    }

    /// @dev Utility function to compute the threshold votes without recomputing the snapshot
    /// Note that `boldAccrued` is a cached value, this function works correctly only when called after an accrual
    function calculateVotingThreshold(uint256 _votes) public view returns (uint256) {
        if (_votes == 0) return 0;

        uint256 minVotes; // to reach MIN_CLAIM: snapshotVotes * MIN_CLAIM / boldAccrued
        uint256 payoutPerVote = boldAccrued * WAD / _votes;
        if (payoutPerVote != 0) {
            minVotes = MIN_CLAIM * WAD / payoutPerVote;
        }
        return max(_votes * VOTING_THRESHOLD_FACTOR / WAD, minVotes);
    }

    // Snapshots votes for the previous epoch and accrues funds for the current epoch
    function _snapshotVotes() internal returns (VoteSnapshot memory snapshot, GlobalState memory state) {
        bool shouldUpdate;
        (snapshot, state, shouldUpdate) = getTotalVotesAndState();

        if (shouldUpdate) {
            votesSnapshot = snapshot;
            uint256 boldBalance = bold.balanceOf(address(this));
            boldAccrued = (boldBalance < MIN_ACCRUAL) ? 0 : boldBalance;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch);
        }
    }

    /// @notice Return the most up to date global snapshot and state as well as a flag to notify whether the state can be updated
    /// This is a convenience function to always retrieve the most up to date state values
    function getTotalVotesAndState()
        public
        view
        returns (VoteSnapshot memory snapshot, GlobalState memory state, bool shouldUpdate)
    {
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

        if (shouldUpdate) {
            votesForInitiativeSnapshot[_initiative] = initiativeSnapshot;
            emit SnapshotVotesForInitiative(_initiative, initiativeSnapshot.votes, initiativeSnapshot.forEpoch);
        }
    }

    /// @dev Given an initiative address, return it's most up to date snapshot and state as well as a flag to notify whether the state can be updated
    /// This is a convenience function to always retrieve the most up to date state values
    function getInitiativeSnapshotAndState(address _initiative)
        public
        view
        returns (
            InitiativeVoteSnapshot memory initiativeSnapshot,
            InitiativeState memory initiativeState,
            bool shouldUpdate
        )
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

    enum InitiativeStatus {
        NONEXISTENT,
        /// This Initiative Doesn't exist | This is never returned
        WARM_UP,
        /// This epoch was just registered
        SKIP,
        /// This epoch will result in no rewards and no unregistering
        CLAIMABLE,
        /// This epoch will result in claiming rewards
        CLAIMED,
        /// The rewards for this epoch have been claimed
        UNREGISTERABLE,
        /// Can be unregistered
        DISABLED // It was already Unregistered

    }

    /// @notice Given an inititive address, updates all snapshots and return the initiative state
    ///     See the view version of `getInitiativeState` for the underlying logic on Initatives FSM
    function getInitiativeState(address _initiative)
        public
        returns (InitiativeStatus status, uint16 lastEpochClaim, uint256 claimableAmount)
    {
        (VoteSnapshot memory votesSnapshot_,) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        return getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);
    }

    /// @dev Given an initiative address and its snapshot, determines the current state for an initiative
    function getInitiativeState(
        address _initiative,
        VoteSnapshot memory _votesSnapshot,
        InitiativeVoteSnapshot memory _votesForInitiativeSnapshot,
        InitiativeState memory _initiativeState
    ) public view returns (InitiativeStatus status, uint16 lastEpochClaim, uint256 claimableAmount) {
        // == Non existent Condition == //
        if (registeredInitiatives[_initiative] == 0) {
            return (InitiativeStatus.NONEXISTENT, 0, 0);
            /// By definition it has zero rewards
        }

        // == Just Registered Condition == //
        if (registeredInitiatives[_initiative] == epoch()) {
            return (InitiativeStatus.WARM_UP, 0, 0);
            /// Was registered this week, cannot have rewards
        }

        // Fetch last epoch at which we claimed
        lastEpochClaim = initiativeStates[_initiative].lastEpochClaim;

        // == Disabled Condition == //
        if (registeredInitiatives[_initiative] == UNREGISTERED_INITIATIVE) {
            return (InitiativeStatus.DISABLED, lastEpochClaim, 0);
            /// By definition it has zero rewards
        }

        // == Already Claimed Condition == //
        if (lastEpochClaim >= epoch() - 1) {
            // early return, we have already claimed
            return (InitiativeStatus.CLAIMED, lastEpochClaim, claimableAmount);
        }

        // NOTE: Pass the snapshot value so we get accurate result
        uint256 votingTheshold = calculateVotingThreshold(_votesSnapshot.votes);

        // If it's voted and can get rewards
        // Votes > calculateVotingThreshold
        // == Rewards Conditions (votes can be zero, logic is the same) == //

        // By definition if _votesForInitiativeSnapshot.votes > 0 then _votesSnapshot.votes > 0
        if (
            _votesForInitiativeSnapshot.votes > votingTheshold
                && !(_votesForInitiativeSnapshot.vetos >= _votesForInitiativeSnapshot.votes)
        ) {
            uint256 claim = _votesForInitiativeSnapshot.votes * boldAccrued / _votesSnapshot.votes;
            return (InitiativeStatus.CLAIMABLE, lastEpochClaim, claim);
        }

        // == Unregister Condition == //
        // e.g. if `UNREGISTRATION_AFTER_EPOCHS` is 4, the 4th epoch flip that would result in SKIP, will result in the initiative being `UNREGISTERABLE`
        if (
            (_initiativeState.lastEpochClaim + UNREGISTRATION_AFTER_EPOCHS < epoch() - 1)
                || _votesForInitiativeSnapshot.vetos > _votesForInitiativeSnapshot.votes
                    && _votesForInitiativeSnapshot.vetos > votingTheshold * UNREGISTRATION_THRESHOLD_FACTOR / WAD
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
        (InitiativeStatus status,,) = getInitiativeState(_initiative);
        require(status == InitiativeStatus.NONEXISTENT, "Governance: initiative-already-registered");

        address userProxyAddress = deriveUserProxyAddress(msg.sender);
        (VoteSnapshot memory snapshot,) = _snapshotVotes();
        UserState memory userState = userStates[msg.sender];

        // an initiative can be registered if the registrant has more voting power (LQTY * age)
        // than the registration threshold derived from the previous epoch's total global votes
        require(
            lqtyToVotes(uint88(stakingV1.stakes(userProxyAddress)), epochStart(), userState.averageStakingTimestamp)
                >= snapshot.votes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-lqty"
        );

        uint16 currentEpoch = epoch();

        registeredInitiatives[_initiative] = currentEpoch;

        emit RegisterInitiative(_initiative, msg.sender, currentEpoch);

        // Replaces try / catch | Enforces sufficient gas is passed
        safeCallWithMinGas(
            _initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onRegisterInitiative, (currentEpoch))
        );
    }

    struct ResetInitiativeData {
        address initiative;
        int88 LQTYVotes;
        int88 LQTYVetos;
    }

    /// @dev Resets an initiative and return the previous votes
    /// NOTE: Technically we don't need vetos
    /// NOTE: Technically we want to populate the `ResetInitiativeData` only when `secondsWithinEpoch() > EPOCH_VOTING_CUTOFF`
    function _resetInitiatives(address[] calldata _initiativesToReset)
        internal
        returns (ResetInitiativeData[] memory)
    {
        ResetInitiativeData[] memory cachedData = new ResetInitiativeData[](_initiativesToReset.length);

        int88[] memory deltaLQTYVotes = new int88[](_initiativesToReset.length);
        int88[] memory deltaLQTYVetos = new int88[](_initiativesToReset.length);

        // Prepare reset data
        for (uint256 i; i < _initiativesToReset.length; i++) {
            Allocation memory alloc = lqtyAllocatedByUserToInitiative[msg.sender][_initiativesToReset[i]];

            // Must be below, else we cannot reset"
            // Makes cast safe
            /// @audit INVARIANT: property_ensure_user_alloc_cannot_dos
            assert(alloc.voteLQTY <= uint88(type(int88).max));
            assert(alloc.vetoLQTY <= uint88(type(int88).max));

            // Cache, used to enforce limits later
            cachedData[i] = ResetInitiativeData({
                initiative: _initiativesToReset[i],
                LQTYVotes: int88(alloc.voteLQTY),
                LQTYVetos: int88(alloc.vetoLQTY)
            });

            // -0 is still 0, so its fine to flip both
            deltaLQTYVotes[i] = -int88(cachedData[i].LQTYVotes);
            deltaLQTYVetos[i] = -int88(cachedData[i].LQTYVetos);
        }

        // RESET HERE || All initiatives will receive most updated data and 0 votes / vetos
        _allocateLQTY(_initiativesToReset, deltaLQTYVotes, deltaLQTYVetos);

        return cachedData;
    }

    /// @inheritdoc IGovernance
    function allocateLQTY(
        address[] calldata _initiativesToReset,
        address[] calldata _initiatives,
        int88[] calldata _absoluteLQTYVotes,
        int88[] calldata _absoluteLQTYVetos
    ) external nonReentrant {
        require(_initiatives.length == _absoluteLQTYVotes.length, "Length");
        require(_absoluteLQTYVetos.length == _absoluteLQTYVotes.length, "Length");

        // To ensure the change is safe, enforce uniqueness
        _requireNoDuplicates(_initiatives);
        _requireNoDuplicates(_initiativesToReset);

        // You MUST always reset
        ResetInitiativeData[] memory cachedData = _resetInitiatives(_initiativesToReset);

        /// Invariant, 0 allocated = 0 votes
        UserState memory userState = userStates[msg.sender];
        require(userState.allocatedLQTY == 0, "must be a reset");

        // After cutoff you can only re-apply the same vote
        // Or vote less
        // Or abstain
        // You can always add a veto, hence we only validate the addition of Votes
        // And ignore the addition of vetos
        // Validate the data here to ensure that the voting is capped at the amount in the other case
        if (secondsWithinEpoch() > EPOCH_VOTING_CUTOFF) {
            // Cap the max votes to the previous cache value
            // This means that no new votes can happen here

            // Removing and VETOING is always accepted
            for (uint256 x; x < _initiatives.length; x++) {
                // If we find it, we ensure it cannot be an increase
                bool found;
                for (uint256 y; y < cachedData.length; y++) {
                    if (cachedData[y].initiative == _initiatives[x]) {
                        found = true;
                        require(_absoluteLQTYVotes[x] <= cachedData[y].LQTYVotes, "Cannot increase");
                        break;
                    }
                }

                // Else we assert that the change is a veto, because by definition the initiatives will have received zero votes past this line
                if (!found) {
                    require(_absoluteLQTYVotes[x] == 0, "Must be zero for new initiatives");
                }
            }
        }

        // Vote here, all values are now absolute changes
        _allocateLQTY(_initiatives, _absoluteLQTYVotes, _absoluteLQTYVetos);
    }

    /// @dev For each given initiative applies relative changes to the allocation
    /// NOTE: Given the current usage the function either: Resets the value to 0, or sets the value to a new value
    ///     Review the flows as the function could be used in many ways, but it ends up being used in just those 2 ways
    function _allocateLQTY(
        address[] memory _initiatives,
        int88[] memory _deltaLQTYVotes,
        int88[] memory _deltaLQTYVetos
    ) internal {
        require(
            _initiatives.length == _deltaLQTYVotes.length && _initiatives.length == _deltaLQTYVetos.length,
            "Governance: array-length-mismatch"
        );

        (VoteSnapshot memory votesSnapshot_, GlobalState memory state) = _snapshotVotes();
        uint16 currentEpoch = epoch();
        UserState memory userState = userStates[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            int88 deltaLQTYVotes = _deltaLQTYVotes[i];
            int88 deltaLQTYVetos = _deltaLQTYVetos[i];

            /// === Check FSM === ///
            // Can vote positively in SKIP, CLAIMABLE, CLAIMED and UNREGISTERABLE states
            // Force to remove votes if disabled
            // Can remove votes and vetos in every stage
            (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
                _snapshotVotesForInitiative(initiative);

            (InitiativeStatus status,,) =
                getInitiativeState(initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);

            if (deltaLQTYVotes > 0 || deltaLQTYVetos > 0) {
                /// @audit FSM CHECK, note that the original version allowed voting on `Unregisterable` Initiatives | This fixes it
                require(
                    status == InitiativeStatus.SKIP || status == InitiativeStatus.CLAIMABLE
                        || status == InitiativeStatus.CLAIMED,
                    "Governance: active-vote-fsm"
                );
            }

            if (status == InitiativeStatus.DISABLED) {
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

            // TODO: Veto reducing total votes logic change
            // TODO: Accounting invariants
            // TODO: Let's say I want to cap the votes vs weights
            // Then by definition, I add the effective LQTY
            // And the effective TS
            // I remove the previous one
            // and add the next one
            // Veto > Vote
            // Reduce down by Vote (cap min)
            // If Vote > Veto
            // Increase by Veto - Veto (reduced max)

            // update the average staking timestamp for all counted voting LQTY
            /// Discount previous only if the initiative was not unregistered

            if (status != InitiativeStatus.DISABLED) {
                /// @audit Trophy: `test_property_sum_of_lqty_global_user_matches_0`
                /// Removing votes from state desynchs the state until all users remove their votes from the initiative
                /// The invariant that holds is: the one that removes the initiatives that have been unregistered
                state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    state.countedVoteLQTYAverageTimestamp,
                    prevInitiativeState.averageStakingTimestampVoteLQTY,
                    /// @audit We don't have a test that fails when this line is changed
                    state.countedVoteLQTY,
                    state.countedVoteLQTY - prevInitiativeState.voteLQTY
                );
                assert(state.countedVoteLQTY >= prevInitiativeState.voteLQTY);
                /// @audit INVARIANT: Never overflows
                state.countedVoteLQTY -= prevInitiativeState.voteLQTY;
            }

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
            safeCallWithMinGas(
                initiative,
                MIN_GAS_TO_HOOK,
                0,
                abi.encodeCall(
                    IInitiative.onAfterAllocateLQTY, (currentEpoch, msg.sender, userState, allocation, initiativeState)
                )
            );
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
        (VoteSnapshot memory votesSnapshot_, GlobalState memory state) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        (InitiativeStatus status,,) =
            getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);
        require(status != InitiativeStatus.NONEXISTENT, "Governance: initiative-not-registered");
        require(status != InitiativeStatus.WARM_UP, "Governance: initiative-in-warm-up");
        require(status == InitiativeStatus.UNREGISTERABLE, "Governance: cannot-unregister-initiative");

        // Remove weight from current state
        uint16 currentEpoch = epoch();

        /// @audit Invariant: Must only claim once or unregister
        // NOTE: Safe to remove | See `check_claim_soundness`
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
        assert(state.countedVoteLQTY >= initiativeState.voteLQTY);
        /// RECON: Overflow
        state.countedVoteLQTY -= initiativeState.voteLQTY;

        globalState = state;

        /// weeks * 2^16 > u32 so the contract will stop working before this is an issue
        registeredInitiatives[_initiative] = UNREGISTERED_INITIATIVE;

        emit UnregisterInitiative(_initiative, currentEpoch);

        // Replaces try / catch | Enforces sufficient gas is passed
        safeCallWithMinGas(
            _initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onUnregisterInitiative, (currentEpoch))
        );
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external nonReentrant returns (uint256) {
        (VoteSnapshot memory votesSnapshot_,) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        (InitiativeStatus status,, uint256 claimableAmount) =
            getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);

        if (status != InitiativeStatus.CLAIMABLE) {
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
        safeCallWithMinGas(
            _initiative,
            MIN_GAS_TO_HOOK,
            0,
            abi.encodeCall(IInitiative.onClaimForInitiative, (votesSnapshot_.forEpoch, claimableAmount))
        );

        return claimableAmount;
    }
}
