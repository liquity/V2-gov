// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max} from "./utils/Math.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, ONE_YEAR, PermitParams} from "./utils/Types.sol";

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
    mapping(address => uint256) public sharesByUser;

    /// @inheritdoc IGovernance
    mapping(address => uint256) public initiativesRegistered;

    /// @inheritdoc IGovernance
    uint256 public boldAccrued;

    /// @inheritdoc IGovernance
    uint256 public qualifyingShares;

    /// @inheritdoc IGovernance
    VoteSnapshot public votesSnapshot;
    /// @inheritdoc IGovernance
    mapping(address => InitiativeVoteSnapshot) public votesForInitiativeSnapshot;

    /// @inheritdoc IGovernance
    mapping(address => UserAllocation) public sharesAllocatedByUser;
    /// @inheritdoc IGovernance
    mapping(address => ShareAllocation) public sharesAllocatedToInitiative;
    // Shares (shares + vetoShares) allocated by user to initiatives
    mapping(address => mapping(address => ShareAllocation)) public sharesAllocatedByUserToInitiative;

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

    /// @inheritdoc IGovernance
    function currentShareRate() public view returns (uint256) {
        return ((block.timestamp - EPOCH_START) * WAD / ONE_YEAR) + WAD;
    }

    function _mintShares(uint256 _lqtyAmount) private returns (uint256) {
        uint256 shareAmount = _lqtyAmount * WAD / currentShareRate();
        sharesByUser[msg.sender] += shareAmount;
        return shareAmount;
    }

    /// @inheritdoc IGovernance
    function depositLQTY(uint256 _lqtyAmount) external returns (uint256 shares) {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy(payable(userProxyAddress)).stake(msg.sender, _lqtyAmount);
        shares = _mintShares(_lqtyAmount);

        emit DepositLQTY(msg.sender, _lqtyAmount, shares);
    }

    /// @inheritdoc IGovernance
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams calldata _permitParams)
        external
        returns (uint256 shares)
    {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy(payable(userProxyAddress)).stakeViaPermit(msg.sender, _lqtyAmount, _permitParams);
        shares = _mintShares(_lqtyAmount);

        emit DepositLQTY(msg.sender, _lqtyAmount, shares);
    }

    /// @inheritdoc IGovernance
    function withdrawLQTY(uint256 _shares) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 shares = sharesByUser[msg.sender];
        UserAllocation memory sharesAllocatedByUser_ = sharesAllocatedByUser[msg.sender];

        // check if user has enough unallocated shares
        require(_shares <= shares - sharesAllocatedByUser_.shares, "Governance: insufficient-unallocated-shares");

        uint256 lqtyAmount = (ILQTYStaking(userProxy.stakingV1()).stakes(address(userProxy)) * _shares) / shares;
        (uint256 accruedLQTY, uint256 accruedLUSD, uint256 accruedETH) =
            userProxy.unstake(lqtyAmount, msg.sender, msg.sender);

        sharesByUser[msg.sender] = shares - _shares;

        emit WithdrawLQTY(msg.sender, lqtyAmount, _shares, accruedLQTY, accruedLUSD, accruedETH);

        return lqtyAmount;
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
    function secondsUntilNextEpoch() public view returns (uint256) {
        return EPOCH_DURATION - ((block.timestamp - EPOCH_START) % EPOCH_DURATION);
    }

    /// @inheritdoc IGovernance
    function sharesToVotes(uint256 _shareRate, uint256 _shares) public pure returns (uint256) {
        uint256 weightedShares = _shares * _shareRate / WAD;
        return weightedShares - _shares;
    }

    /// @inheritdoc IGovernance
    function calculateVotingThreshold() public view returns (uint256) {
        uint256 minVotes;
        uint256 snapshotVotes = votesSnapshot.votes;
        if (snapshotVotes != 0) {
            uint256 payoutPerVote = (boldAccrued * WAD) / snapshotVotes;
            if (payoutPerVote != 0) {
                minVotes = (MIN_CLAIM * WAD) / payoutPerVote;
            }
        }
        return max(snapshotVotes * VOTING_THRESHOLD_FACTOR / WAD, minVotes);
    }

    // Snapshots votes for the previous epoch and accrues funds for the current epoch
    function _snapshotVotes(uint256 _shareRate) internal returns (VoteSnapshot memory snapshot) {
        uint16 currentEpoch = epoch();
        snapshot = votesSnapshot;
        if (snapshot.forEpoch < currentEpoch - 1) {
            snapshot.shareRate = _shareRate;
            snapshot.votes = uint240(sharesToVotes(snapshot.shareRate, qualifyingShares));
            snapshot.forEpoch = currentEpoch - 1;
            votesSnapshot = snapshot;
            boldAccrued = bold.balanceOf(address(this));
            boldAccrued = (boldAccrued < MIN_ACCRUAL) ? 0 : boldAccrued;
            emit SnapshotVotes(snapshot.votes, snapshot.forEpoch, snapshot.shareRate);
        }
    }

    // Snapshots votes for an initiative for the previous epoch but only count the votes
    // if the received votes meet the voting threshold
    function _snapshotVotesForInitiative(address _initiative, uint256 _shareRateSnapshot)
        internal
        returns (InitiativeVoteSnapshot memory)
    {
        uint16 currentEpoch = epoch();
        InitiativeVoteSnapshot memory snapshot = votesForInitiativeSnapshot[_initiative];
        if (snapshot.forEpoch < currentEpoch - 1) {
            uint256 votingThreshold = calculateVotingThreshold();
            ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
            uint256 votes = sharesToVotes(_shareRateSnapshot, shareAllocation.shares);
            uint256 vetos = sharesToVotes(_shareRateSnapshot, shareAllocation.vetoShares);
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

    /// @inheritdoc IGovernance
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot)
    {
        voteSnapshot = _snapshotVotes(currentShareRate());
        initiativeVoteSnapshot = _snapshotVotesForInitiative(_initiative, voteSnapshot.shareRate);
    }

    /// @inheritdoc IGovernance
    function registerInitiative(address _initiative) external {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);

        require(_initiative != address(0), "Governance: zero-address");
        require(initiativesRegistered[_initiative] == 0, "Governance: initiative-already-registered");

        uint256 shareRate = currentShareRate();

        VoteSnapshot memory snapshot = _snapshotVotes(shareRate);
        require(
            sharesToVotes(shareRate, sharesByUser[msg.sender]) >= snapshot.votes * REGISTRATION_THRESHOLD_FACTOR / WAD,
            "Governance: insufficient-shares"
        );

        initiativesRegistered[_initiative] = block.timestamp;

        emit RegisterInitiative(_initiative, msg.sender, epoch());

        try IInitiative(_initiative).onRegisterInitiative() {} catch {}
    }

    /// @inheritdoc IGovernance
    function unregisterInitiative(address _initiative) external {
        VoteSnapshot memory snapshot = _snapshotVotes(currentShareRate());
        InitiativeVoteSnapshot memory votesForInitiativeSnapshot_ =
            _snapshotVotesForInitiative(_initiative, snapshot.shareRate);
        ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
        uint256 vetosForInitiative = sharesToVotes(snapshot.shareRate, shareAllocation.vetoShares);

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

    /// @inheritdoc IGovernance
    function allocateShares(
        address[] calldata _initiatives,
        int256[] calldata _deltaShares,
        int256[] calldata _deltaVetoShares
    ) external nonReentrant {
        uint256 shareRate = currentShareRate();
        VoteSnapshot memory snapshot = _snapshotVotes(shareRate);

        uint256 votingThreshold = calculateVotingThreshold();
        UserAllocation memory sharesAllocatedByUser_ = sharesAllocatedByUser[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            require(
                initiativesRegistered[initiative] + EPOCH_DURATION <= block.timestamp,
                "Governance: initiative-not-active"
            );
            _snapshotVotesForInitiative(initiative, snapshot.shareRate);

            int256 deltaShares = _deltaShares[i];
            require(
                deltaShares <= 0 || deltaShares >= 0 && secondsUntilNextEpoch() >= EPOCH_DURATION - EPOCH_VOTING_CUTOFF,
                "Governance: epoch-voting-cutoff"
            );

            ShareAllocation memory sharesAllocatedToInitiative_ = sharesAllocatedToInitiative[initiative];

            // Add or remove the initiatives shares count from the global qualifying shares count if the initiative
            // meets the voting threshold or not
            uint256 votesForInitiative = sharesToVotes(shareRate, sharesAllocatedToInitiative_.shares);
            if (deltaShares > 0) {
                if (votesForInitiative + sharesToVotes(shareRate, uint256(deltaShares)) >= votingThreshold) {
                    if (votesForInitiative < votingThreshold) {
                        qualifyingShares += sharesAllocatedToInitiative_.shares + uint256(deltaShares);
                    } else {
                        qualifyingShares += uint256(deltaShares);
                    }
                }
            } else if (deltaShares < 0) {
                if (votesForInitiative >= votingThreshold) {
                    if (votesForInitiative - sharesToVotes(shareRate, uint256(-deltaShares)) >= votingThreshold) {
                        qualifyingShares -= uint256(-deltaShares);
                    } else {
                        qualifyingShares -= sharesAllocatedToInitiative_.shares;
                    }
                }
            }

            ShareAllocation memory sharesAllocatedByUserToInitiative_ =
                sharesAllocatedByUserToInitiative[msg.sender][initiative];

            sharesAllocatedByUser_.shares = add(sharesAllocatedByUser_.shares, deltaShares);
            sharesAllocatedToInitiative_.shares = add(sharesAllocatedToInitiative_.shares, deltaShares);
            sharesAllocatedByUserToInitiative_.shares = add(sharesAllocatedByUserToInitiative_.shares, deltaShares);

            int256 deltaVetoShares = _deltaVetoShares[i];
            if (deltaVetoShares != 0) {
                sharesAllocatedByUser_.shares = add(sharesAllocatedByUser_.shares, deltaVetoShares);
                sharesAllocatedToInitiative_.vetoShares = add(sharesAllocatedToInitiative_.vetoShares, deltaVetoShares);
                sharesAllocatedByUserToInitiative_.vetoShares =
                    add(sharesAllocatedByUserToInitiative_.vetoShares, deltaVetoShares);
            }

            sharesAllocatedToInitiative[initiative] = sharesAllocatedToInitiative_;
            sharesAllocatedByUserToInitiative[msg.sender][initiative] = sharesAllocatedByUserToInitiative_;

            emit AllocateShares(msg.sender, initiative, deltaShares, deltaVetoShares, epoch());

            try IInitiative(initiative).onAfterAllocateShares(msg.sender, deltaShares, deltaVetoShares) {} catch {}
        }

        require(
            sharesAllocatedByUser_.shares == 0 || sharesAllocatedByUser_.shares <= sharesByUser[msg.sender],
            "Governance: insufficient-or-unallocated-shares"
        );

        sharesAllocatedByUser_.atEpoch = epoch();
        sharesAllocatedByUser[msg.sender] = sharesAllocatedByUser_;
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external returns (uint256) {
        VoteSnapshot memory votesSnapshot_ = _snapshotVotes(currentShareRate());
        InitiativeVoteSnapshot memory votesForInitiativeSnapshot_ =
            _snapshotVotesForInitiative(_initiative, votesSnapshot_.shareRate);
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
