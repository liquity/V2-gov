// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {_add, max} from "./utils/Math.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, PermitParams} from "./utils/Types.sol";

/// @title Governance: Modular Initiative based Governance
contract Governance is Multicall, UserProxyFactory, ReentrancyGuard, IGovernance {
    using SafeERC20 for IERC20;

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

    constructor(
        address _lqty,
        address _lusd,
        address _stakingV1,
        address _bold,
        Configuration memory _config,
        address[] memory _initiatives
    ) UserProxyFactory(_lqty, _lusd, _stakingV1) {
        lqty = IERC20(_lqty);
        bold = IERC20(_bold);
        require(_config.minClaim <= _config.minAccrual, "Gov: min-claim-gt-min-accrual");
        REGISTRATION_FEE = _config.registrationFee;
        REGISTRATION_THRESHOLD_FACTOR = _config.regstrationThresholdFactor;
        VOTING_THRESHOLD_FACTOR = _config.votingThresholdFactor;
        MIN_CLAIM = _config.minClaim;
        MIN_ACCRUAL = _config.minAccrual;
        EPOCH_START = _config.epochStart;
        require(_config.epochDuration > 0, "Gov: epoch-duration-zero");
        EPOCH_DURATION = _config.epochDuration;
        require(_config.epochVotingCutoff < _config.epochDuration, "Gov: epoch-voting-cutoff-gt-epoch-duration");
        EPOCH_VOTING_CUTOFF = _config.epochVotingCutoff;
        for (uint256 i = 0; i < _initiatives.length; i++) {
            initiativeStates[_initiatives[i]] = InitiativeState(0, 0, 0, 0, epoch(), 0);
        }
    }

    function _averageAge(uint32 _currentTimestamp, uint32 _averageTimestamp) internal pure returns (uint32) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function _calculateAverageTimestamp(
        uint32 _prevOuterAverageTimestamp, // initiativeAllocations[_initiative].averageTimestamp
        uint32 _newInnerAverageTimestamp, // userAllocations[_initiative].averageTimestamp post update // for userAverageTimestamp block.timestamp
        uint96 _prevLQTYBalance,
        uint96 _newLQTYBalance
    ) internal view returns (uint32) {
        // currentAge_ = block.timestamp - initiatives[_initiative].vote.timestamp
        // votingAge_ = block.timestamp - deposit[_address].timestamp
        // currentStake_ = initiatives[_initiative].vote.stake
        // newAge_ = (currentAge_ * currentStake_ + votingAge_ * _stake) / (currentAge_ + votingAge_)

        // return (_prevOuterAverageTimestamp * _newLQTYBalance + _newInnerAverageTimestamp * (_newLQTYBalance - _prevLQTYBalance))
        //         / (_prevOuterAverageTimestamp + _newInnerAverageTimestamp);

        // return (outerAverageAge * _newLQTYBalance + innerAverageAge * _newLQTYBalance - _prevLQTYBalance) / (outerAvergeAge + innerAverageAge);

        // return currentTimestamp - ((currentTimestamp - _prevAverageTimestamp) * _prevLQTYBalance * WAD) / _newLQTYBalance;

        uint32 prevOuterAverageAge = _averageAge(uint32(block.timestamp), _prevOuterAverageTimestamp);
        uint32 newInnerAverageAge = _averageAge(uint32(block.timestamp), _newInnerAverageTimestamp);

        uint96 newOuterAverageAge;
        if (_prevLQTYBalance <= _newLQTYBalance) {
            uint96 deltaLQTY = _newLQTYBalance - _prevLQTYBalance;
            uint32 deltaAge = newInnerAverageAge; // prevOuterAverageAge - newInnerAverageAge;
            if (_prevLQTYBalance + deltaLQTY == 0) {
                newOuterAverageAge = 0;
            } else {
                newOuterAverageAge =
                    (_prevLQTYBalance * prevOuterAverageAge + deltaLQTY * deltaAge) / (_prevLQTYBalance + deltaLQTY);
            }
        } else {
            uint96 deltaLQTY = _prevLQTYBalance - _newLQTYBalance;
            uint32 deltaAge = newInnerAverageAge; // newInnerAverageAge - prevOuterAverageAge;
            if (deltaLQTY >= _prevLQTYBalance) {
                newOuterAverageAge = 0;
            } else {
                newOuterAverageAge =
                    (_prevLQTYBalance * prevOuterAverageAge - deltaLQTY * deltaAge) / (_prevLQTYBalance - deltaLQTY);
            }
        }

        return uint32(block.timestamp - newOuterAverageAge);
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint96 _lqtyAmount) private {
        // uint256 currentTimestamp = block.timestamp;

        // uint256 averageStakingTimestamp_ = averageStakingTimestampByUser[msg.sender];
        // uint256 prevTotalStakedLQTY = _newTotalStakedLQTY - _depositedLQTY;
        // averageStakingTimestamp_ = currentTimestamp
        //     - ((currentTimestamp - averageStakingTimestamp_) * prevTotalStakedLQTY * WAD) / _newTotalStakedLQTY;
        // averageStakingTimestampByUser[msg.sender] = uint64(averageStakingTimestamp_);

        // uint256 globalAverageStakedTimestamp_ = globalAverageStakedTimestamp;
        // uint256 globalLQTYStaked_ = globalLQTYStaked;
        // globalAverageStakedTimestamp = (
        //     currentTimestamp
        //         - ((currentTimestamp - globalAverageStakedTimestamp_) * globalLQTYStaked * WAD)
        //             / (globalLQTYStaked + _depositedLQTY)
        // );

        // globalLQTYStaked = globalLQTYStaked_ + _depositedLQTY;

        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint96 lqtyStaked = uint96(userProxy.staked());

        // update the average staked timestamp for LQTY staked by the user
        UserState memory userState = userStates[msg.sender];
        userState.averageStakingTimestamp = _calculateAverageTimestamp(
            userState.averageStakingTimestamp, uint32(block.timestamp), lqtyStaked, lqtyStaked + _lqtyAmount
        );
        userStates[msg.sender] = userState;

        // update the average staked timestamp for all LQTY staked
        GlobalState memory state = globalState;
        state.totalStakedLQTYAverageTimestamp = _calculateAverageTimestamp(
            state.totalStakedLQTYAverageTimestamp,
            uint32(block.timestamp),
            state.totalStakedLQTY,
            state.totalStakedLQTY + _lqtyAmount
        );
        state.totalStakedLQTY += _lqtyAmount;
        globalState = state;
    }

    /// @inheritdoc IGovernance
    function depositLQTY(uint96 _lqtyAmount) external nonReentrant {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        _deposit(_lqtyAmount);

        UserProxy userProxy = UserProxy(payable(userProxyAddress));
        userProxy.stake(_lqtyAmount, msg.sender);

        emit DepositLQTY(msg.sender, _lqtyAmount);
    }

    /// @inheritdoc IGovernance
    function depositLQTYViaPermit(uint96 _lqtyAmount, PermitParams calldata _permitParams) external nonReentrant {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        _deposit(_lqtyAmount);

        UserProxy userProxy = UserProxy(payable(userProxyAddress));
        userProxy.stakeViaPermit(_lqtyAmount, msg.sender, _permitParams);

        emit DepositLQTY(msg.sender, _lqtyAmount);
    }

    /// @inheritdoc IGovernance
    function withdrawLQTY(uint96 _lqtyAmount) external {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 lqtyStaked = userProxy.staked();

        UserState storage userState = userStates[msg.sender];

        // check if user has enough unallocated lqty
        require(_lqtyAmount <= lqtyStaked - userState.allocatedLQTY, "Governance: insufficient-unallocated-lqty");

        // update the average staked timestamp for all LQTY staked
        GlobalState memory state = globalState;
        state.totalStakedLQTY -= _lqtyAmount;
        globalState = state;

        // TODO: remove accruedLQTY
        (uint256 accruedLQTY, uint256 accruedLUSD, uint256 accruedETH) =
            userProxy.unstake(_lqtyAmount, msg.sender, msg.sender);

        emit WithdrawLQTY(msg.sender, _lqtyAmount, accruedLQTY, accruedLUSD, accruedETH);
    }

    /// @inheritdoc IGovernance
    function claimFromStakingV1(address _rewardRecipient) external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(0, _rewardRecipient, _rewardRecipient);
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
    function lqtyToVotes(uint96 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp)
        public
        pure
        returns (uint240)
    {
        return _lqtyAmount * _averageAge(uint32(_currentTimestamp), _averageTimestamp);
    }

    /// @inheritdoc IGovernance
    function calculateVotingThreshold() public view returns (uint256) {
        uint256 snapshotVotes = votesSnapshot.votes;
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
        uint16 currentEpoch = epoch();
        snapshot = votesSnapshot;
        state = globalState;
        if (snapshot.forEpoch < currentEpoch - 1) {
            snapshot.votes = lqtyToVotes(state.countedVoteLQTY, epochStart(), state.countedVoteLQTYAverageTimestamp);
            snapshot.forEpoch = currentEpoch - 1;
            votesSnapshot = snapshot;
            uint256 boldBalance = bold.balanceOf(address(this));
            boldAccrued = (boldBalance < MIN_ACCRUAL) ? 0 : boldBalance;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch);
        }
    }

    // Snapshots votes for an initiative for the previous epoch but only count the votes
    // if the received votes meet the voting threshold
    function _snapshotVotesForInitiative(address _initiative)
        internal
        returns (InitiativeVoteSnapshot memory initiativeSnapshot, InitiativeState memory initiativeState)
    {
        uint16 currentEpoch = epoch();
        initiativeSnapshot = votesForInitiativeSnapshot[_initiative];
        initiativeState = initiativeStates[_initiative];
        if (initiativeSnapshot.forEpoch < currentEpoch - 1) {
            uint256 votingThreshold = calculateVotingThreshold();
            uint32 start = epochStart();
            uint240 votes = lqtyToVotes(initiativeState.voteLQTY, start, initiativeState.averageStakingTimestamp);
            uint240 vetos = lqtyToVotes(initiativeState.vetoLQTY, start, initiativeState.averageStakingTimestamp);
            // if the votes didn't meet the voting threshold then no votes qualify
            if (votes >= votingThreshold && votes >= vetos) {
                initiativeSnapshot.votes = votes;
            }
            initiativeSnapshot.forEpoch = currentEpoch - 1;
            votesForInitiativeSnapshot[_initiative] = initiativeSnapshot;
            emit SnapshotVotesForInitiative(_initiative, initiativeSnapshot.votes, initiativeSnapshot.forEpoch);
        }
    }

    /// @inheritdoc IGovernance
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot)
    {
        (voteSnapshot,) = _snapshotVotes();
        (initiativeVoteSnapshot,) = _snapshotVotesForInitiative(_initiative);
    }

    /// @inheritdoc IGovernance
    function registerInitiative(address _initiative) external {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);

        require(_initiative != address(0), "Governance: zero-address");
        require(initiativeStates[_initiative].atEpoch == 0, "Governance: initiative-already-registered");

        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        (VoteSnapshot memory snapshot,) = _snapshotVotes();

        UserState memory userState = userStates[msg.sender];

        require(
            lqtyToVotes(userProxy.staked(), block.timestamp, userState.averageStakingTimestamp)
                >= snapshot.votes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-lqty"
        );

        initiativeStates[_initiative] = InitiativeState(0, 0, 0, 0, epoch(), 0);

        emit RegisterInitiative(_initiative, msg.sender, epoch());

        try IInitiative(_initiative).onRegisterInitiative() {} catch {}
    }

    /// @inheritdoc IGovernance
    function unregisterInitiative(address _initiative) external {
        (, GlobalState memory state) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_, InitiativeState memory initiativeState) =
            _snapshotVotesForInitiative(_initiative);

        uint256 vetosForInitiative =
            lqtyToVotes(initiativeState.vetoLQTY, block.timestamp, initiativeState.averageStakingTimestamp);

        require(
            (votesForInitiativeSnapshot_.votes == 0 && votesForInitiativeSnapshot_.forEpoch + 4 < epoch())
                || (
                    vetosForInitiative > votesForInitiativeSnapshot_.votes
                        && vetosForInitiative > calculateVotingThreshold() * 3
                ),
            "Governance: cannot-unregister-initiative"
        );

        if (initiativeState.counted == 1) {
            state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                state.countedVoteLQTYAverageTimestamp,
                initiativeState.averageStakingTimestamp,
                state.countedVoteLQTY,
                state.countedVoteLQTY - initiativeState.voteLQTY
            );
            state.countedVoteLQTY -= initiativeState.voteLQTY;
            globalState = state;
        }

        delete initiativeStates[_initiative];

        emit UnregisterInitiative(_initiative, epoch());

        try IInitiative(_initiative).onUnregisterInitiative() {} catch {}
    }

    /// @inheritdoc IGovernance
    function allocateLQTY(
        address[] calldata _initiatives,
        int192[] calldata _deltaLQTYVotes,
        int192[] calldata _deltaLQTYVetos
    ) external nonReentrant {
        (, GlobalState memory state) = _snapshotVotes();

        uint256 votingThreshold = calculateVotingThreshold();
        uint16 currentEpoch = epoch();

        UserState memory userState = userStates[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            int192 deltaLQTYVotes = _deltaLQTYVotes[i];
            int192 deltaLQTYVetos = _deltaLQTYVetos[i];

            require(
                deltaLQTYVotes <= 0 || deltaLQTYVotes >= 0 && secondsWithinEpoch() <= EPOCH_VOTING_CUTOFF,
                "Governance: epoch-voting-cutoff"
            );

            (, InitiativeState memory initiativeState) = _snapshotVotesForInitiative(initiative);
            require(
                initiativeState.active == 1 || currentEpoch > initiativeState.atEpoch,
                "Governance: initiative-not-active"
            );
            initiativeState.active = 1;

            InitiativeState memory prevInitiativeState = InitiativeState(
                initiativeState.voteLQTY,
                initiativeState.vetoLQTY,
                initiativeState.counted,
                initiativeState.active,
                initiativeState.atEpoch,
                initiativeState.averageStakingTimestamp
            );

            userState.allocatedLQTY = _add(userState.allocatedLQTY, deltaLQTYVotes + deltaLQTYVetos);

            initiativeState.averageStakingTimestamp = _calculateAverageTimestamp(
                initiativeState.averageStakingTimestamp,
                userState.averageStakingTimestamp,
                initiativeState.voteLQTY + initiativeState.vetoLQTY,
                _add(initiativeState.voteLQTY + initiativeState.vetoLQTY, deltaLQTYVotes + deltaLQTYVetos)
            );

            initiativeState.voteLQTY = _add(initiativeState.voteLQTY, deltaLQTYVotes);
            initiativeState.vetoLQTY = _add(initiativeState.vetoLQTY, deltaLQTYVetos);

            uint240 votesForInitiative = lqtyToVotes(
                initiativeState.voteLQTY + initiativeState.vetoLQTY,
                block.timestamp,
                initiativeState.averageStakingTimestamp
            );

            initiativeState.counted = (votesForInitiative >= votingThreshold) ? 1 : 0;
            initiativeState.atEpoch = currentEpoch;
            initiativeStates[initiative] = initiativeState;

            if (prevInitiativeState.counted == 1) {
                state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    state.countedVoteLQTYAverageTimestamp,
                    initiativeState.averageStakingTimestamp,
                    state.countedVoteLQTY,
                    state.countedVoteLQTY - prevInitiativeState.voteLQTY
                );
                state.countedVoteLQTY -= prevInitiativeState.voteLQTY;
            }

            if (initiativeState.counted == 1) {
                state.countedVoteLQTYAverageTimestamp = _calculateAverageTimestamp(
                    state.countedVoteLQTYAverageTimestamp,
                    initiativeState.averageStakingTimestamp,
                    state.countedVoteLQTY,
                    state.countedVoteLQTY + initiativeState.voteLQTY
                );
                state.countedVoteLQTY += initiativeState.voteLQTY;
            }

            Allocation memory allocation = lqtyAllocatedByUserToInitiative[msg.sender][initiative];
            allocation.voteLQTY = _add(allocation.voteLQTY, deltaLQTYVotes);
            allocation.vetoLQTY = _add(allocation.vetoLQTY, deltaLQTYVetos);
            allocation.atEpoch = currentEpoch;
            lqtyAllocatedByUserToInitiative[msg.sender][initiative] = allocation;

            emit AllocateLQTY(msg.sender, initiative, deltaLQTYVotes, deltaLQTYVetos, currentEpoch);

            try IInitiative(initiative).onAfterAllocateShares(msg.sender, allocation.voteLQTY, allocation.vetoLQTY) {}
                catch {}
        }

        require(
            userState.allocatedLQTY == 0
                || userState.allocatedLQTY <= UserProxy(payable(deriveUserProxyAddress(msg.sender))).staked(),
            "Governance: insufficient-or-unallocated-shares"
        );

        globalState = state;
        userStates[msg.sender] = userState;
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external returns (uint256) {
        (VoteSnapshot memory votesSnapshot_,) = _snapshotVotes();
        (InitiativeVoteSnapshot memory votesForInitiativeSnapshot_,) = _snapshotVotesForInitiative(_initiative);
        if (votesForInitiativeSnapshot_.votes == 0) return 0;

        uint256 claim = votesForInitiativeSnapshot_.votes * boldAccrued / votesSnapshot_.votes;

        votesForInitiativeSnapshot_.votes = 0;
        votesForInitiativeSnapshot[_initiative] = votesForInitiativeSnapshot_; // implicitly prevents double claiming

        bold.safeTransfer(_initiative, claim);

        emit ClaimForInitiative(_initiative, claim, votesSnapshot_.forEpoch);

        try IInitiative(_initiative).onClaimForInitiative(claim) {} catch {}

        return claim;
    }
}
