// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

import {add, max} from "./utils/Math.sol";
import {Multicall} from "./utils/Multicall.sol";
import {WAD, ONE_YEAR, PermitParams} from "./utils/Types.sol";

contract Governance is Multicall, UserProxyFactory, IGovernance {
    using SafeERC20 for IERC20;

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
    uint256 public totalShares;
    /// @inheritdoc IGovernance
    mapping(address => uint256) public sharesByUser;

    /// @inheritdoc IGovernance
    mapping(address => uint256) public initiativesRegistered;

    /// @inheritdoc IGovernance
    uint256 public boldAccrued;

    /// @inheritdoc IGovernance
    uint256 public qualifyingShares;

    /// @inheritdoc IGovernance
    Snapshot public votesSnapshot;
    /// @inheritdoc IGovernance
    mapping(address => Snapshot) public votesForInitiativeSnapshot;

    /// @inheritdoc IGovernance
    mapping(address => uint256) public sharesAllocatedByUser;
    /// @inheritdoc IGovernance
    mapping(address => ShareAllocation) public sharesAllocatedToInitiative;
    // Shares (shares + vetoShares) allocated by user to initiatives
    mapping(address => mapping(address => ShareAllocation)) public sharesAllocatedByUserToInitiative;

    constructor(
        address _lqty,
        address _lusd,
        address _stakingV1,
        address _bold,
        uint256 _minClaim,
        uint256 _minAccrual,
        uint256 _registrationFee,
        uint256 _epochStart,
        uint256 _epochDuration,
        uint256 _epochVotingCutoff
    ) UserProxyFactory(_lqty, _lusd, _stakingV1) {
        bold = IERC20(_bold);
        require(_minClaim <= _minAccrual, "Gov: min-claim-gt-min-accrual");
        MIN_CLAIM = _minClaim;
        MIN_ACCRUAL = _minAccrual;
        REGISTRATION_FEE = _registrationFee;
        EPOCH_START = _epochStart;
        require(_epochDuration > 0, "Gov: epoch-duration-zero");
        EPOCH_DURATION = _epochDuration;
        require(_epochVotingCutoff < _epochDuration, "Gov: epoch-voting-cutoff-gt-epoch-duration");
        EPOCH_VOTING_CUTOFF = _epochVotingCutoff;
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
    function depositLQTY(uint256 _lqtyAmount) external returns (uint256) {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy(payable(userProxyAddress)).stake(msg.sender, _lqtyAmount);
        return _mintShares(_lqtyAmount);
    }

    /// @inheritdoc IGovernance
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams calldata _permitParams)
        external
        returns (uint256)
    {
        address userProxyAddress = deriveUserProxyAddress(msg.sender);

        if (userProxyAddress.code.length == 0) {
            deployUserProxy();
        }

        UserProxy(payable(userProxyAddress)).stakeViaPermit(msg.sender, _lqtyAmount, _permitParams);
        return _mintShares(_lqtyAmount);
    }

    /// @inheritdoc IGovernance
    function withdrawShares(uint256 _shareAmount) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 shares = sharesByUser[msg.sender];

        // check if user has enough unallocated shares
        require(
            _shareAmount <= shares - sharesAllocatedByUser[msg.sender], "Governance: insufficient-unallocated-shares"
        );

        uint256 lqtyAmount = (ILQTYStaking(userProxy.stakingV1()).stakes(address(userProxy)) * _shareAmount) / shares;
        userProxy.unstake(msg.sender, lqtyAmount);

        sharesByUser[msg.sender] = shares - _shareAmount;

        return lqtyAmount;
    }

    /// @inheritdoc IGovernance
    function claimFromStakingV1() external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(msg.sender, 0);
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
        return max(snapshotVotes * 0.04e18 / WAD, minVotes);
    }

    // Snapshots votes for the previous epoch and accrues funds for the current epoch
    function _snapshotVotes(uint256 _shareRate) internal returns (Snapshot memory) {
        uint16 currentEpoch = epoch();
        Snapshot memory snapshot = votesSnapshot;
        if (snapshot.forEpoch < currentEpoch - 1) {
            snapshot.votes = uint240(sharesToVotes(_shareRate, qualifyingShares));
            snapshot.forEpoch = currentEpoch - 1;
            votesSnapshot = snapshot;
            boldAccrued = bold.balanceOf(address(this));
            boldAccrued = (boldAccrued < MIN_ACCRUAL) ? 0 : boldAccrued;
        }
        return snapshot;
    }

    // Snapshots votes for an initiative for the previous epoch but only count the votes
    // if the received votes meet the voting threshold
    function _snapshotVotesForInitiative(uint256 _shareRate, address _initiative) internal returns (Snapshot memory) {
        uint16 currentEpoch = epoch();
        Snapshot memory snapshot = votesForInitiativeSnapshot[_initiative];
        if (snapshot.forEpoch < currentEpoch - 1) {
            uint256 votingThreshold = calculateVotingThreshold();
            ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
            uint256 votes = sharesToVotes(_shareRate, shareAllocation.shares);
            uint256 vetos = sharesToVotes(_shareRate, shareAllocation.vetoShares);
            // if the votes didn't meet the voting threshold then no votes qualify
            if (votes >= votingThreshold && votes >= vetos) {
                snapshot.votes = uint240(votes);
            }
            snapshot.forEpoch = currentEpoch - 1;
            votesForInitiativeSnapshot[_initiative] = snapshot;
        }
        return snapshot;
    }

    /// @inheritdoc IGovernance
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (Snapshot memory votes, Snapshot memory votesForInitiative)
    {
        uint256 shareRate = currentShareRate();
        votes = _snapshotVotes(shareRate);
        votesForInitiative = _snapshotVotesForInitiative(shareRate, _initiative);
    }

    /// @inheritdoc IGovernance
    function registerInitiative(address _initiative) external {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);
        require(_initiative != address(0), "Governance: zero-address");
        require(initiativesRegistered[_initiative] == 0, "Governance: initiative-already-registered");
        initiativesRegistered[_initiative] = block.timestamp;
    }

    /// @inheritdoc IGovernance
    function unregisterInitiative(address _initiative) external {
        uint256 shareRate = currentShareRate();
        _snapshotVotes(shareRate);
        Snapshot memory votesForInitiativeSnapshot_ = _snapshotVotesForInitiative(shareRate, _initiative);
        ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
        uint256 vetosForInitiative = sharesToVotes(shareRate, shareAllocation.vetoShares);

        require(
            (votesForInitiativeSnapshot_.votes == 0 && votesForInitiativeSnapshot_.forEpoch + 4 < epoch())
                || vetosForInitiative > votesForInitiativeSnapshot_.votes
                    && votesForInitiativeSnapshot_.votes > calculateVotingThreshold() * 3,
            "Governance: cannot-unregister-initiative"
        );

        delete initiativesRegistered[_initiative];
    }

    /// @inheritdoc IGovernance
    function allocateShares(
        address[] calldata _initiatives,
        int256[] calldata _deltaShares,
        int256[] calldata _deltaVetoShares
    ) external {
        uint256 shareRate = currentShareRate();
        _snapshotVotes(shareRate);

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 sharesAllocatedByUser_ = sharesAllocatedByUser[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            require(
                initiativesRegistered[initiative] + EPOCH_DURATION <= block.timestamp,
                "Governance: initiative-not-active"
            );
            _snapshotVotesForInitiative(shareRate, initiative);

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

            sharesAllocatedByUser_ = add(sharesAllocatedByUser_, deltaShares);
            sharesAllocatedToInitiative_.shares = add(sharesAllocatedToInitiative_.shares, deltaShares);
            sharesAllocatedByUserToInitiative_.shares = add(sharesAllocatedByUserToInitiative_.shares, deltaShares);

            int256 deltaVetoShares = _deltaVetoShares[i];
            if (deltaVetoShares != 0) {
                sharesAllocatedByUser_ = add(sharesAllocatedByUser_, deltaVetoShares);
                sharesAllocatedToInitiative_.vetoShares = add(sharesAllocatedToInitiative_.vetoShares, deltaVetoShares);
                sharesAllocatedByUserToInitiative_.vetoShares =
                    add(sharesAllocatedByUserToInitiative_.vetoShares, deltaVetoShares);
            }

            sharesAllocatedToInitiative[initiative] = sharesAllocatedToInitiative_;
            sharesAllocatedByUserToInitiative[msg.sender][initiative] = sharesAllocatedByUserToInitiative_;
        }

        require(
            sharesAllocatedByUser_ == 0 || sharesAllocatedByUser_ == sharesByUser[msg.sender],
            "Governance: insufficient-or-unallocated-shares"
        );

        sharesAllocatedByUser[msg.sender] = sharesAllocatedByUser_;
    }

    /// @inheritdoc IGovernance
    function claimForInitiative(address _initiative) external returns (uint256) {
        uint256 shareRate = currentShareRate();
        Snapshot memory votesSnapshot_ = _snapshotVotes(shareRate);
        Snapshot memory votesForInitiativeSnapshot_ = _snapshotVotesForInitiative(shareRate, _initiative);
        if (votesForInitiativeSnapshot_.votes == 0) return 0;

        uint256 claim = votesForInitiativeSnapshot_.votes * boldAccrued / votesSnapshot_.votes;

        votesForInitiativeSnapshot_.votes = 0;
        votesForInitiativeSnapshot[_initiative] = votesForInitiativeSnapshot_; // implicitly prevents double claiming

        bold.safeTransfer(_initiative, claim);

        return claim;
    }
}
