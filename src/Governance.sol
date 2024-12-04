// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max} from "./utils/Math.sol";
import {_requireNoDuplicates, _requireNoNegatives} from "./utils/UniqueArray.sol";
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

    // 100 Million LQTY will be necessary to make the rounding error cause 1 second of loss per operation
    uint120 public constant TIMESTAMP_PRECISION = 1e26;

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
        UNREGISTRATION_AFTER_EPOCHS = _config.unregistrationAfterEpochs;

        // Voting threshold must be below 100% of votes
        require(_config.votingThresholdFactor < WAD, "Gov: voting-config");
        VOTING_THRESHOLD_FACTOR = _config.votingThresholdFactor;

        MIN_CLAIM = _config.minClaim;
        MIN_ACCRUAL = _config.minAccrual;
        require(_config.epochStart <= block.timestamp, "Gov: cannot-start-in-future");
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
        for (uint256 i = 0; i < _initiatives.length; i++) {
            // Register initial initiatives in the earliest possible epoch, which lets us make them votable immediately
            // post-deployment if we so choose, by backdating the first epoch at least EPOCH_DURATION in the past.
            registeredInitiatives[_initiatives[i]] = 1;

            bool success = safeCallWithMinGas(
                _initiatives[i], MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onRegisterInitiative, (1))
            );

            emit RegisterInitiative(_initiatives[i], msg.sender, 1, success);
        }

        _renounceOwnership();
    }

    function _averageAge(uint120 _currentTimestamp, uint120 _averageTimestamp) internal pure returns (uint120) {
        // Due to rounding error, _averageTimestamp can sometimes be higher than _currentTimestamp
        if (_currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function _calculateAverageTimestamp(
        uint256 _prevOuterAverageTimestamp,
        uint256 _newInnerAverageTimestamp,
        uint256 _prevLQTYBalance,
        uint256 _newLQTYBalance
    ) internal pure returns (uint120) {
        if (_newLQTYBalance == 0) return 0;

        return uint120(
            _newInnerAverageTimestamp + _prevOuterAverageTimestamp * _prevLQTYBalance / _newLQTYBalance
                - _newInnerAverageTimestamp * _prevLQTYBalance / _newLQTYBalance
        );
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    function _updateUserTimestamp(uint88 _lqtyAmount) private returns (UserProxy) {
        require(_lqtyAmount > 0, "Governance: zero-lqty-amount");

        // Assert that we have resetted here
        UserState memory userState = userStates[msg.sender];
        require(userState.allocatedLQTY == 0, "Governance: must-be-zero-allocation");

        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy userProxy = UserProxy(payable(userProxyAddress));

        uint88 lqtyStaked = uint88(stakingV1.stakes(userProxyAddress));

        // update the average staked timestamp for LQTY staked by the user

        // NOTE: Upscale user TS by `TIMESTAMP_PRECISION`
        userState.averageStakingTimestamp = _calculateAverageTimestamp(
            userState.averageStakingTimestamp,
            uint120(block.timestamp) * uint120(TIMESTAMP_PRECISION),
            lqtyStaked,
            lqtyStaked + _lqtyAmount
        );
        userStates[msg.sender] = userState;

        emit DepositLQTY(msg.sender, _lqtyAmount);

        return userProxy;
    }

    /// @inheritdoc IGovernance
    function depositLQTY(uint88 _lqtyAmount) external {
        depositLQTY(_lqtyAmount, false, msg.sender);
    }

    function depositLQTY(uint88 _lqtyAmount, bool _doSendRewards, address _recipient) public nonReentrant {
        UserProxy userProxy = _updateUserTimestamp(_lqtyAmount);
        userProxy.stake(_lqtyAmount, msg.sender, _doSendRewards, _recipient);
    }

    /// @inheritdoc IGovernance
    function depositLQTYViaPermit(uint88 _lqtyAmount, PermitParams calldata _permitParams) external {
        depositLQTYViaPermit(_lqtyAmount, _permitParams, false, msg.sender);
    }

    function depositLQTYViaPermit(
        uint88 _lqtyAmount,
        PermitParams calldata _permitParams,
        bool _doSendRewards,
        address _recipient
    ) public nonReentrant {
        UserProxy userProxy = _updateUserTimestamp(_lqtyAmount);
        userProxy.stakeViaPermit(_lqtyAmount, msg.sender, _permitParams, _doSendRewards, _recipient);
    }

    /// @inheritdoc IGovernance
    function withdrawLQTY(uint88 _lqtyAmount) external {
        withdrawLQTY(_lqtyAmount, true, msg.sender);
    }

    function withdrawLQTY(uint88 _lqtyAmount, bool _doSendRewards, address _recipient) public nonReentrant {
        // check that user has reset before changing lqty balance
        UserState storage userState = userStates[msg.sender];
        require(userState.allocatedLQTY == 0, "Governance: must-allocate-zero");

        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        require(address(userProxy).code.length != 0, "Governance: user-proxy-not-deployed");

        uint88 lqtyStaked = uint88(stakingV1.stakes(address(userProxy)));

        (uint256 accruedLUSD, uint256 accruedETH) = userProxy.unstake(_lqtyAmount, _doSendRewards, _recipient);

        emit WithdrawLQTY(msg.sender, _lqtyAmount, accruedLUSD, accruedETH);
    }

    /// @inheritdoc IGovernance
    function claimFromStakingV1(address _rewardRecipient) external returns (uint256 accruedLUSD, uint256 accruedETH) {
        address payable userProxyAddress = payable(deriveUserProxyAddress(msg.sender));
        require(userProxyAddress.code.length != 0, "Governance: user-proxy-not-deployed");
        return UserProxy(userProxyAddress).unstake(0, true, _rewardRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernance
    function epoch() public view returns (uint16) {
        return uint16(((block.timestamp - EPOCH_START) / EPOCH_DURATION) + 1);
    }

    /// @inheritdoc IGovernance
    function epochStart() public view returns (uint32) {
        return uint32(EPOCH_START + (epoch() - 1) * EPOCH_DURATION);
    }

    /// @inheritdoc IGovernance
    function secondsWithinEpoch() public view returns (uint32) {
        return uint32((block.timestamp - EPOCH_START) % EPOCH_DURATION);
    }

    /// @inheritdoc IGovernance
    function lqtyToVotes(uint88 _lqtyAmount, uint120 _currentTimestamp, uint120 _averageTimestamp)
        public
        pure
        returns (uint208)
    {
        return uint208(_lqtyAmount) * uint208(_averageAge(_currentTimestamp, _averageTimestamp));
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

    /// @inheritdoc IGovernance
    function calculateVotingThreshold() public returns (uint256) {
        (VoteSnapshot memory snapshot,) = _snapshotVotes();

        return calculateVotingThreshold(snapshot.votes);
    }

    /// @inheritdoc IGovernance
    function calculateVotingThreshold(uint256 _votes) public view returns (uint256) {
        if (_votes == 0) return 0;

        uint256 minVotes; // to reach MIN_CLAIM: snapshotVotes * MIN_CLAIM / boldAccrued
        uint256 payoutPerVote = boldAccrued * WAD / _votes;
        if (payoutPerVote != 0) {
            minVotes = MIN_CLAIM * WAD / payoutPerVote;
        }
        return max(_votes * VOTING_THRESHOLD_FACTOR / WAD, minVotes);
    }

    // Snapshots votes at the end of the previous epoch
    // Accrues funds until the first activity of the current epoch, which are valid throughout all of the current epoch
    function _snapshotVotes() internal returns (VoteSnapshot memory snapshot, GlobalState memory state) {
        bool shouldUpdate;
        (snapshot, state, shouldUpdate) = getTotalVotesAndState();

        if (shouldUpdate) {
            votesSnapshot = snapshot;
            uint256 boldBalance = bold.balanceOf(address(this));
            boldAccrued = (boldBalance < MIN_ACCRUAL) ? 0 : boldBalance;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch, boldAccrued);
        }
    }

    /// @inheritdoc IGovernance
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

            snapshot.votes = lqtyToVotes(
                state.countedVoteLQTY,
                uint120(epochStart()) * uint120(TIMESTAMP_PRECISION),
                state.countedVoteLQTYAverageTimestamp
            );
            snapshot.forEpoch = currentEpoch - 1;
        }
    }

    // Snapshots votes for an initiative for the previous epoch
    function _snapshotVotesForInitiative(address _initiative)
        internal
        returns (InitiativeVoteSnapshot memory initiativeSnapshot, InitiativeState memory initiativeState)
    {
        bool shouldUpdate;
        (initiativeSnapshot, initiativeState, shouldUpdate) = getInitiativeSnapshotAndState(_initiative);

        if (shouldUpdate) {
            votesForInitiativeSnapshot[_initiative] = initiativeSnapshot;
            emit SnapshotVotesForInitiative(
                _initiative, initiativeSnapshot.votes, initiativeSnapshot.vetos, initiativeSnapshot.forEpoch
            );
        }
    }

    /// @inheritdoc IGovernance
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

            uint120 start = uint120(epochStart()) * uint120(TIMESTAMP_PRECISION);
            uint208 votes =
                lqtyToVotes(initiativeState.voteLQTY, start, initiativeState.averageStakingTimestampVoteLQTY);
            uint208 vetos =
                lqtyToVotes(initiativeState.vetoLQTY, start, initiativeState.averageStakingTimestampVetoLQTY);
            // NOTE: Upscaling to u224 is safe
            initiativeSnapshot.votes = votes;
            initiativeSnapshot.vetos = vetos;

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
        uint16 initiativeRegistrationEpoch = registeredInitiatives[_initiative];

        // == Non existent Condition == //
        if (initiativeRegistrationEpoch == 0) {
            return (InitiativeStatus.NONEXISTENT, 0, 0);
            /// By definition it has zero rewards
        }

        uint16 currentEpoch = epoch();

        // == Just Registered Condition == //
        if (initiativeRegistrationEpoch == currentEpoch) {
            return (InitiativeStatus.WARM_UP, 0, 0);
            /// Was registered this week, cannot have rewards
        }

        // Fetch last epoch at which we claimed
        lastEpochClaim = initiativeStates[_initiative].lastEpochClaim;

        // == Disabled Condition == //
        if (initiativeRegistrationEpoch == UNREGISTERED_INITIATIVE) {
            return (InitiativeStatus.DISABLED, lastEpochClaim, 0);
            /// By definition it has zero rewards
        }

        // == Already Claimed Condition == //
        if (lastEpochClaim >= currentEpoch - 1) {
            // early return, we have already claimed
            return (InitiativeStatus.CLAIMED, lastEpochClaim, claimableAmount);
        }

        // NOTE: Pass the snapshot value so we get accurate result
        uint256 votingTheshold = calculateVotingThreshold(_votesSnapshot.votes);

        // If it's voted and can get rewards
        // Votes > calculateVotingThreshold
        // == Rewards Conditions (votes can be zero, logic is the same) == //

        // By definition if _votesForInitiativeSnapshot.votes > 0 then _votesSnapshot.votes > 0

        uint256 upscaledInitiativeVotes = uint256(_votesForInitiativeSnapshot.votes);
        uint256 upscaledInitiativeVetos = uint256(_votesForInitiativeSnapshot.vetos);
        uint256 upscaledTotalVotes = uint256(_votesSnapshot.votes);

        if (upscaledInitiativeVotes > votingTheshold && !(upscaledInitiativeVetos >= upscaledInitiativeVotes)) {
            /// @audit 2^208 means we only have 2^48 left
            /// Therefore we need to scale the value down by 4 orders of magnitude to make it fit
            assert(upscaledInitiativeVotes * 1e14 / (VOTING_THRESHOLD_FACTOR / 1e4) > upscaledTotalVotes);

            // 34 times when using 0.03e18 -> 33.3 + 1-> 33 + 1 = 34
            uint256 CUSTOM_PRECISION = WAD / VOTING_THRESHOLD_FACTOR + 1;

            /// @audit Because of the updated timestamp, we can run into overflows if we multiply by `boldAccrued`
            ///     We use `CUSTOM_PRECISION` for this reason, a smaller multiplicative value
            ///     The change SHOULD be safe because we already check for `threshold` before getting into these lines
            /// As an alternative, this line could be replaced by https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
            uint256 claim =
                upscaledInitiativeVotes * CUSTOM_PRECISION / upscaledTotalVotes * boldAccrued / CUSTOM_PRECISION;
            return (InitiativeStatus.CLAIMABLE, lastEpochClaim, claim);
        }

        // == Unregister Condition == //
        // e.g. if `UNREGISTRATION_AFTER_EPOCHS` is 4, the 4th epoch flip that would result in SKIP, will result in the initiative being `UNREGISTERABLE`
        if (
            (_initiativeState.lastEpochClaim + UNREGISTRATION_AFTER_EPOCHS < currentEpoch - 1)
                || upscaledInitiativeVetos > upscaledInitiativeVotes
                    && upscaledInitiativeVetos > votingTheshold * UNREGISTRATION_THRESHOLD_FACTOR / WAD
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

        uint256 upscaledSnapshotVotes = uint256(snapshot.votes);
        require(
            lqtyToVotes(
                uint88(stakingV1.stakes(userProxyAddress)),
                uint120(epochStart()) * uint120(TIMESTAMP_PRECISION),
                userState.averageStakingTimestamp
            ) >= upscaledSnapshotVotes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-lqty"
        );

        uint16 currentEpoch = epoch();

        registeredInitiatives[_initiative] = currentEpoch;

        /// @audit This ensures that the initiatives has UNREGISTRATION_AFTER_EPOCHS even after the first epoch
        initiativeStates[_initiative].lastEpochClaim = currentEpoch - 1;

        // Replaces try / catch | Enforces sufficient gas is passed
        bool success = safeCallWithMinGas(
            _initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onRegisterInitiative, (currentEpoch))
        );

        emit RegisterInitiative(_initiative, msg.sender, currentEpoch, success);
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
            require(alloc.voteLQTY > 0 || alloc.vetoLQTY > 0, "Governance: nothing to reset");

            // Must be below, else we cannot reset"
            // Makes cast safe
            /// @audit Check INVARIANT: property_ensure_user_alloc_cannot_dos
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

    /// @notice Reset the allocations for the initiatives being passed, must pass all initiatives else it will revert
    ///     NOTE: If you reset at the last day of the epoch, you won't be able to vote again
    ///         Use `allocateLQTY` to reset and vote
    function resetAllocations(address[] calldata _initiativesToReset, bool checkAll) external nonReentrant {
        _requireNoDuplicates(_initiativesToReset);
        _resetInitiatives(_initiativesToReset);

        // NOTE: In most cases, the check will pass
        // But if you allocate too many initiatives, we may run OOG
        // As such the check is optional here
        // All other calls to the system enforce this
        // So it's recommended that your last call to `resetAllocations` passes the check
        if (checkAll) {
            require(userStates[msg.sender].allocatedLQTY == 0, "Governance: must be a reset");
        }
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
        _requireNoDuplicates(_initiativesToReset);
        _requireNoDuplicates(_initiatives);

        // Explicit >= 0 checks for all values since we reset values below
        _requireNoNegatives(_absoluteLQTYVotes);
        _requireNoNegatives(_absoluteLQTYVetos);
        // If the goal is to remove all votes from an initiative, including in _initiativesToReset is enough
        _requireNoNOP(_absoluteLQTYVotes, _absoluteLQTYVetos);

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

    // Avoid "stack too deep" by placing these variables in memory
    struct AllocateLQTYMemory {
        VoteSnapshot votesSnapshot_;
        GlobalState state;
        UserState userState;
        InitiativeVoteSnapshot votesForInitiativeSnapshot_;
        InitiativeState initiativeState;
        InitiativeState prevInitiativeState;
        Allocation allocation;
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

        AllocateLQTYMemory memory vars;
        (vars.votesSnapshot_, vars.state) = _snapshotVotes();
        uint16 currentEpoch = epoch();
        vars.userState = userStates[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            int88 deltaLQTYVotes = _deltaLQTYVotes[i];
            int88 deltaLQTYVetos = _deltaLQTYVetos[i];
            assert(deltaLQTYVotes != 0 || deltaLQTYVetos != 0);

            /// === Check FSM === ///
            // Can vote positively in SKIP, CLAIMABLE and CLAIMED states
            // Force to remove votes if disabled
            // Can remove votes and vetos in every stage
            (vars.votesForInitiativeSnapshot_, vars.initiativeState) = _snapshotVotesForInitiative(initiative);

            (InitiativeStatus status,,) = getInitiativeState(
                initiative, vars.votesSnapshot_, vars.votesForInitiativeSnapshot_, vars.initiativeState
            );

            if (deltaLQTYVotes > 0 || deltaLQTYVetos > 0) {
                /// @audit You cannot vote on `unregisterable` but a vote may have been there
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
            vars.prevInitiativeState = InitiativeState(
                vars.initiativeState.voteLQTY,
                vars.initiativeState.vetoLQTY,
                vars.initiativeState.averageStakingTimestampVoteLQTY,
                vars.initiativeState.averageStakingTimestampVetoLQTY,
                vars.initiativeState.lastEpochClaim
            );

            // update the average staking timestamp for the initiative based on the user's average staking timestamp
            vars.initiativeState.averageStakingTimestampVoteLQTY = _calculateAverageTimestamp(
                vars.initiativeState.averageStakingTimestampVoteLQTY,
                vars.userState.averageStakingTimestamp,
                /// @audit This is wrong unless we enforce a reset on deposit and withdrawal
                vars.initiativeState.voteLQTY,
                add(vars.initiativeState.voteLQTY, deltaLQTYVotes)
            );
            vars.initiativeState.averageStakingTimestampVetoLQTY = _calculateAverageTimestamp(
                vars.initiativeState.averageStakingTimestampVetoLQTY,
                vars.userState.averageStakingTimestamp,
                /// @audit This is wrong unless we enforce a reset on deposit and withdrawal
                vars.initiativeState.vetoLQTY,
                add(vars.initiativeState.vetoLQTY, deltaLQTYVetos)
            );

            // allocate the voting and vetoing LQTY to the initiative
            vars.initiativeState.voteLQTY = add(vars.initiativeState.voteLQTY, deltaLQTYVotes);
            vars.initiativeState.vetoLQTY = add(vars.initiativeState.vetoLQTY, deltaLQTYVetos);

            // update the initiative's state
            initiativeStates[initiative] = vars.initiativeState;

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

            /// @audit We update the state only for non-disabled initiaitives
            /// Disabled initiaitves have had their totals subtracted already
            /// Math is also non associative so we cannot easily compare values
            if (status != InitiativeStatus.DISABLED) {
                /// @audit Trophy: `test_property_sum_of_lqty_global_user_matches_0`
                /// Removing votes from state desynchs the state until all users remove their votes from the initiative
                /// The invariant that holds is: the one that removes the initiatives that have been unregistered
                vars.state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    vars.state.countedVoteLQTYAverageTimestamp,
                    vars.prevInitiativeState.averageStakingTimestampVoteLQTY,
                    /// @audit We don't have a test that fails when this line is changed
                    vars.state.countedVoteLQTY,
                    vars.state.countedVoteLQTY - vars.prevInitiativeState.voteLQTY
                );
                assert(vars.state.countedVoteLQTY >= vars.prevInitiativeState.voteLQTY);
                /// @audit INVARIANT: Never overflows
                vars.state.countedVoteLQTY -= vars.prevInitiativeState.voteLQTY;

                vars.state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    vars.state.countedVoteLQTYAverageTimestamp,
                    vars.initiativeState.averageStakingTimestampVoteLQTY,
                    vars.state.countedVoteLQTY,
                    vars.state.countedVoteLQTY + vars.initiativeState.voteLQTY
                );

                vars.state.countedVoteLQTY += vars.initiativeState.voteLQTY;
            }

            // == USER ALLOCATION == //

            // allocate the voting and vetoing LQTY to the initiative
            vars.allocation = lqtyAllocatedByUserToInitiative[msg.sender][initiative];
            vars.allocation.voteLQTY = add(vars.allocation.voteLQTY, deltaLQTYVotes);
            vars.allocation.vetoLQTY = add(vars.allocation.vetoLQTY, deltaLQTYVetos);
            vars.allocation.atEpoch = currentEpoch;
            require(!(vars.allocation.voteLQTY != 0 && vars.allocation.vetoLQTY != 0), "Governance: vote-and-veto");
            lqtyAllocatedByUserToInitiative[msg.sender][initiative] = vars.allocation;

            // == USER STATE == //

            vars.userState.allocatedLQTY = add(vars.userState.allocatedLQTY, deltaLQTYVotes + deltaLQTYVetos);

            // Replaces try / catch | Enforces sufficient gas is passed
            bool success = safeCallWithMinGas(
                initiative,
                MIN_GAS_TO_HOOK,
                0,
                abi.encodeCall(
                    IInitiative.onAfterAllocateLQTY,
                    (currentEpoch, msg.sender, vars.userState, vars.allocation, vars.initiativeState)
                )
            );

            emit AllocateLQTY(msg.sender, initiative, deltaLQTYVotes, deltaLQTYVetos, currentEpoch, success);
        }

        require(
            vars.userState.allocatedLQTY == 0
                || vars.userState.allocatedLQTY <= uint88(stakingV1.stakes(deriveUserProxyAddress(msg.sender))),
            "Governance: insufficient-or-allocated-lqty"
        );

        globalState = vars.state;
        userStates[msg.sender] = vars.userState;
    }

    /// @inheritdoc IGovernance
    function unregisterInitiative(address _initiative) external nonReentrant {
        /// Enforce FSM
        (VoteSnapshot memory votesSnapshot_, GlobalState memory state) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        (InitiativeStatus status,,) =
            getInitiativeState(_initiative, votesSnapshot_, votesForInitiativeSnapshot_, initiativeState);
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

        // Replaces try / catch | Enforces sufficient gas is passed
        bool success = safeCallWithMinGas(
            _initiative, MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onUnregisterInitiative, (currentEpoch))
        );

        emit UnregisterInitiative(_initiative, currentEpoch, success);
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external nonReentrant returns (uint256) {
        // Accrue and update state
        (VoteSnapshot memory votesSnapshot_,) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        // Compute values on accrued state
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

        // @audit INVARIANT, because of rounding errors the system can overpay
        /// We upscale the timestamp to reduce the impact of the loss
        /// However this is still possible
        uint256 available = bold.balanceOf(address(this));
        if (claimableAmount > available) {
            claimableAmount = available;
        }

        bold.safeTransfer(_initiative, claimableAmount);

        // Replaces try / catch | Enforces sufficient gas is passed
        bool success = safeCallWithMinGas(
            _initiative,
            MIN_GAS_TO_HOOK,
            0,
            abi.encodeCall(IInitiative.onClaimForInitiative, (votesSnapshot_.forEpoch, claimableAmount))
        );

        emit ClaimForInitiative(_initiative, claimableAmount, votesSnapshot_.forEpoch, success);

        return claimableAmount;
    }

    function _requireNoNOP(int88[] memory _absoluteLQTYVotes, int88[] memory _absoluteLQTYVetos) internal pure {
        for (uint256 i; i < _absoluteLQTYVotes.length; i++) {
            require(_absoluteLQTYVotes[i] > 0 || _absoluteLQTYVetos[i] > 0, "Governance: voting nothing");
        }
    }
}
