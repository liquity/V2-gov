// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {StakingV2, WAD} from "./StakingV2.sol";
import {Collector} from "./Collector.sol";

function add(uint256 a, int256 b) pure returns (uint128) {
    if (b < 0) {
        return uint128(a - uint256(-b));
    }
    return uint128(a + uint256(b));
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}

// Terminology:
//   Shares: Allocated by users (stakers) to initiatives
//   VetoShares: Allocated by users (stakers to initiatives they reject
//   QualifingShares: Shares that are included in the vote count (incl. initiatives that meet the voting threshold)
//   Votes: Derived from the shares allocated to initiatives
contract VotingV2 {
    using SafeERC20 for IERC20;

    // Duration of an epoch in seconds (1 week)
    uint256 public constant EPOCH_DURATION = 604800;
    // Reference timestamp used to derive the current share rate
    uint256 public immutable DEPLOYMENT_TIMESTAMP = block.timestamp;
    // Minimum BOLD amount that can be claimed, if an initiative doesn't have enough votes to meet the criteria
    // then it's votes a excluded from the vote count and distribution
    uint256 public immutable MIN_CLAIM = 0.05e18;
    // Minimum amount of BOLD that have to be accrued for an epoch, otherwise accrual will be skipped for that epoch
    uint256 public immutable MIN_ACCRUAL = 0.05e18;
    // Amount of BOLD to be paid in order to register a new initiative
    uint256 public immutable REGISTRATION_FEE = 100e18;

    StakingV2 public immutable stakingV2;
    IERC20 public immutable bold;
    address public immutable collector;

    // Initiatives registered, by address
    mapping(address => uint256) public initiativesRegistered;

    // Total number of shares allocated to initiatives that meet the voting threshold and are included in vote counting
    uint256 public qualifyingShares;

    struct Snapshot {
        uint240 votes;
        uint16 forEpoch;
    }

    // Number of votes at the last epoch
    Snapshot public votesSnapshot;
    // Number of votes received by an initiative at the last epoch
    mapping(address => Snapshot) public votesForInitiativeSnapshot;

    struct ShareAllocation {
        uint128 shares; // Shares allocated vouching for the initiative
        uint128 vetoShares; // Shares vetoing the initiative
    }

    // Number of shares (shares + vetoShares) allocated by user
    mapping(address => uint256) public sharesAllocatedByUser;
    // Shares (shares + vetoShares) allocated to initiatives
    mapping(address => ShareAllocation) public sharesAllocatedToInitiative;
    // Shares (shares + vetoShares) allocated by user to initiatives
    mapping(address => mapping(address => ShareAllocation)) public sharesAllocatedByUserToInitiative;

    // BOLD accrued since last epoch
    uint256 public boldAccrued;

    constructor(
        address _stakingV2,
        address _bold,
        address _collector,
        uint256 _minClaim,
        uint256 _minAccrual,
        uint256 _registrationFee
    ) {
        stakingV2 = StakingV2(_stakingV2);
        bold = IERC20(_bold);
        collector = _collector;
        require(_minClaim <= _minAccrual, "Voting: min-claim-gt-min-accrual");
        MIN_CLAIM = _minClaim;
        MIN_ACCRUAL = _minAccrual;
        REGISTRATION_FEE = _registrationFee;
    }

    // Returns the current epoch number
    function epoch() public view returns (uint16) {
        return uint16(((block.timestamp - DEPLOYMENT_TIMESTAMP) / EPOCH_DURATION) + 1);
    }

    // Voting power of a share linearly increases over time starting from 0 at time of share issuance
    function sharesToVotes(uint256 _shareRate, uint256 _shares) public pure returns (uint256) {
        uint256 weightedShares = _shares * _shareRate / WAD;
        return weightedShares - _shares;
    }

    // Voting threshold is the max. of either:
    //   - 4% of total shares allocated in the previous epoch
    //   - or the minimum number of votes necessary to claim at least MIN_CLAIM BOLD
    function calculateVotingThreshold() public view returns (uint256) {
        uint256 minVotes;
        Snapshot memory snapshot = votesSnapshot;
        if (snapshot.votes != 0) {
            uint256 payoutPerVote = (boldAccrued * WAD) / snapshot.votes;
            if (payoutPerVote != 0) {
                minVotes = (MIN_CLAIM * WAD) / payoutPerVote;
            }
        }
        return max(snapshot.votes * 0.04e18 / WAD, minVotes);
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

    // Snapshots votes for the previous epoch and accrues funds for the current epoch
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (Snapshot memory votes, Snapshot memory votesForInitiative)
    {
        uint256 shareRate = stakingV2.currentShareRate();
        votes = _snapshotVotes(shareRate);
        votesForInitiative = _snapshotVotesForInitiative(shareRate, _initiative);
    }

    // Registers a new initiative
    function registerInitiative(address _initiative) external {
        bold.safeTransferFrom(msg.sender, address(this), REGISTRATION_FEE);
        require(_initiative != address(0), "Voting: zero-address");
        require(initiativesRegistered[_initiative] == 0, "Voting: initiative-already-registered");
        initiativesRegistered[_initiative] = block.timestamp;
    }

    // Unregisters an initiative if it didn't receive enough votes in the last 4 epochs
    // or if it received more vetos than votes and the number of vetos are greater than 3 times the voting threshold
    function unregisterInitiative(address _initiative) external {
        uint256 shareRate = stakingV2.currentShareRate();
        _snapshotVotes(shareRate);
        Snapshot memory votesForInitiativeSnapshot_ = _snapshotVotesForInitiative(shareRate, _initiative);
        ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
        uint256 vetosForInitiative = sharesToVotes(shareRate, shareAllocation.vetoShares);

        require(
            (votesForInitiativeSnapshot_.votes == 0 && votesForInitiativeSnapshot_.forEpoch + 4 < epoch())
                || vetosForInitiative > votesForInitiativeSnapshot_.votes
                    && votesForInitiativeSnapshot_.votes > calculateVotingThreshold() * 3,
            "Voting: cannot-unregister-initiative"
        );

        delete initiativesRegistered[_initiative];
    }

    // Allocates the user's shares to initiatives either as vote shares or veto shares
    function allocateShares(
        address[] calldata _initiatives,
        int256[] calldata _deltaShares,
        int256[] calldata _deltaVetoShares
    ) external {
        uint256 shareRate = stakingV2.currentShareRate();
        _snapshotVotes(shareRate);

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 sharesAllocatedByUser_ = sharesAllocatedByUser[msg.sender];

        for (uint256 i = 0; i < _initiatives.length; i++) {
            address initiative = _initiatives[i];
            require(
                initiativesRegistered[initiative] <= block.timestamp + EPOCH_DURATION, "Voting: initiative-not-active"
            );
            _snapshotVotesForInitiative(shareRate, initiative);

            int256 deltaShares = _deltaShares[i];
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
            sharesAllocatedByUser_ == 0 || sharesAllocatedByUser_ == stakingV2.sharesByUser(msg.sender),
            "Voting: insufficient-or-unallocated-shares"
        );

        sharesAllocatedByUser[msg.sender] = sharesAllocatedByUser_;
    }

    // split accrued funds according to votes received between all initiatives
    function claimForInitiative(address _initiative) external returns (uint256) {
        uint256 shareRate = stakingV2.currentShareRate();
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
