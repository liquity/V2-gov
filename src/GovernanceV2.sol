// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IGovernanceV2} from "./interfaces/IGovernanceV2.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max} from "./utils/Math.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, ONE_YEAR, PermitParams} from "./utils/Types.sol";

/// @title Governance: Modular Initiative based Governance
contract GovernanceV2 is Multicall, UserProxyFactory, ReentrancyGuard, IGovernanceV2 {
    using SafeERC20 for IERC20;

    IERC20 public immutable lqty;
    /// @inheritdoc IGovernanceV2
    IERC20 public immutable bold;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable EPOCH_START;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable EPOCH_DURATION;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable EPOCH_VOTING_CUTOFF;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable MIN_CLAIM;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable MIN_ACCRUAL;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable REGISTRATION_FEE;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable REGISTRATION_THRESHOLD_FACTOR;
    /// @inheritdoc IGovernanceV2
    uint256 public immutable VOTING_THRESHOLD_FACTOR;

    /// @inheritdoc IGovernanceV2
    mapping(address => uint256) public initiativesRegistered;

    /// @inheritdoc IGovernanceV2
    uint256 public boldAccrued;

    /// @inheritdoc IGovernanceV2
    uint256 public qualifyingLQTY;

    /// @inheritdoc IGovernanceV2
    VoteSnapshot public votesSnapshot;
    /// @inheritdoc IGovernanceV2
    mapping(address => InitiativeVoteSnapshot) public votesForInitiativeSnapshot;

    uint256 public globalAverageStakedTimestamp;
    uint256 public globalLQTYStaked;

    /// @inheritdoc IGovernanceV2
    mapping(address => uint256) public lqtyAllocatedByUser;
    mapping(address => uint256) public averageStakedTimestampByUser;
    /// @inheritdoc IGovernanceV2
    mapping(address => AllocationAtEpoch) public lqtyAllocatedToInitiative;
    mapping(address => uint256) public averageStakedTimestampByInitiative;
    // Shares (shares + vetoShares) allocated by user to initiatives
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
            initiativesRegistered[_initiatives[i]] = block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 _newTotalStakedLQTY, uint256 _depositedLQTY) private returns (uint256) {
        uint256 currentTimestamp = block.timestamp;

        uint256 averageStakedTimestamp_ = averageStakedTimestampByUser[msg.sender];
        uint256 prevTotalStakedLQTY = _newTotalStakedLQTY - _depositedLQTY;
        averageStakedTimestamp_ = currentTimestamp
            - ((currentTimestamp - averageStakedTimestamp_) * prevTotalStakedLQTY * WAD) / _newTotalStakedLQTY;
        averageStakedTimestampByUser[msg.sender] = uint64(averageStakedTimestamp_);

        uint256 globalAverageStakedTimestamp_ = globalAverageStakedTimestamp;
        uint256 globalLQTYStaked_ = globalLQTYStaked;
        globalAverageStakedTimestamp = (
            currentTimestamp
                - ((currentTimestamp - globalAverageStakedTimestamp_) * globalLQTYStaked * WAD)
                    / (globalLQTYStaked + _depositedLQTY)
        );

        globalLQTYStaked = globalLQTYStaked_ + _depositedLQTY;

        return averageStakedTimestamp_;
    }

    function _withdraw(uint256 _withdrawnLQTY) private {
        globalLQTYStaked -= _withdrawnLQTY;
    }

    /// @inheritdoc IGovernanceV2
    function depositLQTY(uint256 _lqtyAmount) external {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy userProxy = UserProxy(payable(userProxyAddress));
        userProxy.stake(_lqtyAmount, msg.sender);
        _deposit(userProxy.staked(), _lqtyAmount);

        emit DepositLQTY(msg.sender, _lqtyAmount);
    }

    /// @inheritdoc IGovernanceV2
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams calldata _permitParams) external {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy userProxy = UserProxy(payable(userProxyAddress));
        userProxy.stakeViaPermit(_lqtyAmount, msg.sender, _permitParams);
        _deposit(userProxy.staked(), _lqtyAmount);

        emit DepositLQTY(msg.sender, _lqtyAmount);
    }

    /// @inheritdoc IGovernanceV2
    function withdrawLQTY(uint240 _lqtyAmount) external {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 lqtyStaked = userProxy.staked();

        // check if user has enough unallocated lqty
        require(
            _lqtyAmount <= lqtyStaked - lqtyAllocatedByUser[msg.sender], "Governance: insufficient-unallocated-lqty"
        );

        _withdraw(_lqtyAmount);

        // TODO: remove accruedLQTY
        (uint256 accruedLQTY, uint256 accruedLUSD, uint256 accruedETH) =
            userProxy.unstake(_lqtyAmount, msg.sender, msg.sender);

        emit WithdrawLQTY(msg.sender, _lqtyAmount, accruedLQTY, accruedLUSD, accruedETH);
    }

    /// @inheritdoc IGovernanceV2
    function claimFromStakingV1(address _rewardRecipient) external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(0, _rewardRecipient, _rewardRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernanceV2
    function epoch() public view returns (uint16) {
        return uint16(((block.timestamp - EPOCH_START) / EPOCH_DURATION) + 1);
    }

    /// @inheritdoc IGovernanceV2
    function secondsDuringCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - EPOCH_START) % EPOCH_DURATION;
    }

    // / @inheritdoc IGovernanceV2
    function userLQTYToVotes(uint256 _lqty) public view returns (uint256) {
        uint256 averageAge = block.timestamp - averageStakedTimestampByUser[msg.sender];
        uint256 globalAverageAge = block.timestamp - globalAverageStakedTimestamp;
        uint256 globalVotingPower = globalAverageAge * globalLQTYStaked;
        uint256 votingPower = averageAge * _lqty / globalVotingPower;
        return _lqty * votingPower;
    }

    function initiativeLQTYToVotes(uint256 _lqty, uint256 timestamp) public view returns (uint256) {
        uint256 averageAge = timestamp - averageStakedTimestampByInitiative[msg.sender];
        uint256 globalAverageAge = timestamp - globalAverageStakedTimestamp;
        uint256 globalVotingPower = globalAverageAge * globalLQTYStaked;
        uint256 votingPower = averageAge * _lqty / globalVotingPower;
        return _lqty * votingPower;
    }

    function globalLQTYToVotes(uint256 _lqty) public view returns (uint256) {
        uint256 globalAverageAge = block.timestamp - globalAverageStakedTimestamp;
        uint256 globalVotingPower = globalAverageAge * globalLQTYStaked;
        return _lqty * globalVotingPower;
    }

    /// @inheritdoc IGovernanceV2
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
    function _snapshotVotes() internal returns (VoteSnapshot memory snapshot) {
        uint16 currentEpoch = epoch();
        snapshot = votesSnapshot;
        if (snapshot.forEpoch < currentEpoch - 1) {
            snapshot.timestamp = block.timestamp;
            snapshot.votes = uint240(globalLQTYToVotes(qualifyingLQTY));
            snapshot.forEpoch = currentEpoch - 1;
            votesSnapshot = snapshot;
            uint256 boldBalance = bold.balanceOf(address(this));
            boldAccrued = (boldBalance < MIN_ACCRUAL) ? 0 : boldBalance;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch);
        }
    }

    // Snapshots votes for an initiative for the previous epoch but only count the votes
    // if the received votes meet the voting threshold
    function _snapshotVotesForInitiative(address _initiative, uint256 _snapshotTimestamp)
        internal
        returns (InitiativeVoteSnapshot memory)
    {
        uint16 currentEpoch = epoch();
        InitiativeVoteSnapshot memory snapshot = votesForInitiativeSnapshot[_initiative];
        if (snapshot.forEpoch < currentEpoch - 1) {
            uint256 votingThreshold = calculateVotingThreshold();
            AllocationAtEpoch memory Allocation = lqtyAllocatedToInitiative[_initiative];
            uint256 votes = initiativeLQTYToVotes(Allocation.voteLQTY, _snapshotTimestamp);
            uint256 vetos = initiativeLQTYToVotes(Allocation.vetoLQTY, _snapshotTimestamp);
            // if the votes didn't meet the voting threshold then no votes qualify
            if (votes >= votingThreshold && votes >= vetos) {
                snapshot.votes = uint240(votes);
            }
            snapshot.forEpoch = currentEpoch - 1;
            votesForInitiativeSnapshot[_initiative] = snapshot;
            emit SnapshotVotesForInitiative(_initiative, snapshot.votes, snapshot.forEpoch);
        }
        return snapshot;
    }

    /// @inheritdoc IGovernanceV2
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot)
    {
        voteSnapshot = _snapshotVotes();
        initiativeVoteSnapshot = _snapshotVotesForInitiative(_initiative, voteSnapshot.timestamp);
    }

    /// @inheritdoc IGovernanceV2
    function registerInitiative(address _initiative) external {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);

        require(_initiative != address(0), "Governance: zero-address");
        require(initiativesRegistered[_initiative] == 0, "Governance: initiative-already-registered");

        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        VoteSnapshot memory snapshot = _snapshotVotes();
        require(
            userLQTYToVotes(userProxy.staked()) >= snapshot.votes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-votes"
        );

        initiativesRegistered[_initiative] = block.timestamp;

        emit RegisterInitiative(_initiative, msg.sender, epoch());

        try IInitiative(_initiative).onRegisterInitiative() {} catch {}
    }

    /// @inheritdoc IGovernanceV2
    function unregisterInitiative(address _initiative) external {
        VoteSnapshot memory snapshot = _snapshotVotes();
        InitiativeVoteSnapshot memory votesForInitiativeSnapshot_ =
            _snapshotVotesForInitiative(_initiative, snapshot.timestamp);
        AllocationAtEpoch memory Allocation = lqtyAllocatedToInitiative[_initiative];
        uint256 vetosForInitiative = initiativeLQTYToVotes(Allocation.vetoLQTY, snapshot.timestamp);

        require(
            (votesForInitiativeSnapshot_.votes == 0 && votesForInitiativeSnapshot_.forEpoch + 4 < epoch())
                || vetosForInitiative > votesForInitiativeSnapshot_.votes
                    && votesForInitiativeSnapshot_.votes > calculateVotingThreshold() * 3,
            "Governance: cannot-unregister-initiative"
        );

        delete initiativesRegistered[_initiative];

        emit UnregisterInitiative(_initiative, epoch());

        try IInitiative(_initiative).onUnregisterInitiative() {} catch {}
    }

    /// @inheritdoc IGovernanceV2
    function allocateLQTY(
        address[] calldata _initiatives,
        int256[] calldata _deltaLQTYVotes,
        int256[] calldata _deltaLQTYVetos
    ) external nonReentrant {
        VoteSnapshot memory snapshot = _snapshotVotes();

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 lqtyAllocatedByUser_ = lqtyAllocatedByUser[msg.sender];

        uint16 currentEpoch = epoch();

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            require(
                initiativesRegistered[initiative] + EPOCH_DURATION <= block.timestamp,
                "Governance: initiative-not-active"
            );
            _snapshotVotesForInitiative(initiative, snapshot.timestamp);

            int256 deltaLQTYVotes = _deltaLQTYVotes[i];
            require(
                deltaLQTYVotes <= 0 || deltaLQTYVotes >= 0 && secondsDuringCurrentEpoch() <= EPOCH_VOTING_CUTOFF,
                "Governance: epoch-voting-cutoff"
            );

            AllocationAtEpoch memory lqtyAllocatedToInitiative_ = lqtyAllocatedToInitiative[initiative];

            // Add or remove the initiatives shares count from the global qualifying shares count if the initiative
            // meets the voting threshold or not
            uint256 votesForInitiative = initiativeLQTYToVotes(lqtyAllocatedToInitiative_.voteLQTY, block.timestamp);
            if (deltaLQTYVotes > 0) {
                if (votesForInitiative >= votingThreshold) {
                    qualifyingLQTY += uint256(deltaLQTYVotes);
                } else {
                    if (
                        votesForInitiative
                            + initiativeLQTYToVotes(
                                lqtyAllocatedToInitiative_.voteLQTY + uint256(deltaLQTYVotes), block.timestamp
                            ) >= votingThreshold
                    ) {
                        qualifyingLQTY += lqtyAllocatedToInitiative_.voteLQTY + uint256(deltaLQTYVotes);
                    }
                }
            } else if (deltaLQTYVotes < 0) {
                if (votesForInitiative >= votingThreshold) {
                    if (
                        votesForInitiative
                            - initiativeLQTYToVotes(
                                lqtyAllocatedToInitiative_.voteLQTY - uint256(-deltaLQTYVotes), block.timestamp
                            ) >= votingThreshold
                    ) {
                        qualifyingLQTY -= uint256(-deltaLQTYVotes);
                    } else {
                        qualifyingLQTY -= lqtyAllocatedToInitiative_.voteLQTY;
                    }
                }
            }

            Allocation memory lqtyAllocatedByUserToInitiative_ = lqtyAllocatedByUserToInitiative[msg.sender][initiative];

            lqtyAllocatedByUser_ = add(lqtyAllocatedByUser_, deltaLQTYVotes);
            lqtyAllocatedToInitiative_.voteLQTY = add(lqtyAllocatedToInitiative_.voteLQTY, deltaLQTYVotes);
            lqtyAllocatedByUserToInitiative_.voteLQTY = add(lqtyAllocatedByUserToInitiative_.voteLQTY, deltaLQTYVotes);

            int256 deltaLQTYVetos = _deltaLQTYVetos[i];
            if (deltaLQTYVetos != 0) {
                lqtyAllocatedByUser_ = add(lqtyAllocatedByUser_, deltaLQTYVetos);
                lqtyAllocatedToInitiative_.vetoLQTY = add(lqtyAllocatedToInitiative_.vetoLQTY, deltaLQTYVetos);
                lqtyAllocatedByUserToInitiative_.vetoLQTY =
                    add(lqtyAllocatedByUserToInitiative_.vetoLQTY, deltaLQTYVetos);
            }

            lqtyAllocatedToInitiative_.atEpoch = currentEpoch;

            lqtyAllocatedToInitiative[initiative] = lqtyAllocatedToInitiative_;
            lqtyAllocatedByUserToInitiative[msg.sender][initiative] = lqtyAllocatedByUserToInitiative_;

            emit AllocateLQTY(msg.sender, initiative, deltaLQTYVotes, deltaLQTYVetos, currentEpoch);

            try IInitiative(initiative).onAfterAllocateShares(
                msg.sender, lqtyAllocatedByUserToInitiative_.voteLQTY, lqtyAllocatedByUserToInitiative_.vetoLQTY
            ) {} catch {}
        }

        require(
            lqtyAllocatedByUser_ == 0
                || lqtyAllocatedByUser_ <= UserProxy(payable(deriveUserProxyAddress(msg.sender))).staked(),
            "Governance: insufficient-or-unallocated-shares"
        );

        lqtyAllocatedByUser[msg.sender] = lqtyAllocatedByUser_;
    }

    /// @inheritdoc IGovernanceV2
    function claimForInitiative(address _initiative) external returns (uint256) {
        VoteSnapshot memory votesSnapshot_ = _snapshotVotes();
        InitiativeVoteSnapshot memory votesForInitiativeSnapshot_ =
            _snapshotVotesForInitiative(_initiative, votesSnapshot_.timestamp);
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
