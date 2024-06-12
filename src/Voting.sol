// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {console} from "forge-std/console.sol";

import {StakingV2, WAD} from "./StakingV2.sol";
import {DoubleLinkedList} from "./DoubleLinkedList.sol";

uint256 constant EPOCH_DURATION = 604800;

function add(uint256 a, int256 b) pure returns (uint128) {
    if (b < 0) {
        return uint128(a - uint256(-b));
    }
    return uint128(a + uint256(b));
}

// Glossary:
//   Shares: Allocated by users (stakers) to initiatives
//   VetoShares: Allocated by users (stakers to initiatives they reject
//   QualifingShares: Shares that are included in the vote count (incl. initiatives that meet the voting threshold)
//   Votes: Derived from the shares allocated to initiatives
contract Voting {
    using SafeERC20 for IERC20;
    using DoubleLinkedList for DoubleLinkedList.List;

    uint256 public immutable deploymentTimestamp = block.timestamp;

    StakingV2 public stakingV2;

    // Initiatives registered by address
    mapping(address => uint256) public initiativesRegistered;

    // Total number of shares allocated to initiatives that meet the voting threshold and are included in vote counting
    uint256 public qualifyingShares;

    struct Snapshot {
        uint248 votes;
        uint8 finalized;
    }

    // Epoch id of the last stored snapshot
    uint256 public lastSnapshotEpoch;
    // Vote snapshots by epoch
    mapping(uint256 => Snapshot) public votesSnapshots;
    // Vote snapshots by epoch and for an initiative
    mapping(uint256 => mapping(address => Snapshot)) votesForInitiativeSnapshots;

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

    // Accrued funds by epoch for each token
    mapping(uint256 => mapping(address => uint256)) public accruedInEpoch;
    // Funds distributed to initiatives in an epoch
    mapping(uint256 => mapping(address => bool)) public distributeToInitiativeInEpoch;

    constructor(address _stakingV2) {
        stakingV2 = StakingV2(_stakingV2);
    }

    // store last epoch
    function epoch() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) / EPOCH_DURATION) + 1;
    }

    // Voting power statically increases over time starting from 0 at time of share issuance
    function sharesToVotes(uint256 _shareRate, uint256 _shares) public pure returns (uint256) {
        uint256 weightedShares = _shares * _shareRate / WAD;
        return weightedShares - _shares;
    }

    // Voting threshold is 4% of total shares allocated in the previous epoch
    function calculateVotingThreshold() public view returns (uint256) {
        return votesSnapshots[lastSnapshotEpoch].votes * 0.04e18 / WAD;
    }

    function _snapshotVotes(uint256 _shareRate) internal returns (uint256) {
        Snapshot memory snapshot = votesSnapshots[epoch() - 1];
        if (snapshot.finalized == 0) {
            snapshot.votes = uint248(sharesToVotes(_shareRate, qualifyingShares));
            snapshot.finalized = 1;
            votesSnapshots[epoch() - 1] = snapshot;
            lastSnapshotEpoch = epoch() - 1;
        }
        return snapshot.votes;
    }

    function _snapshotVotesForInitiative(uint256 _shareRate, address _initiative) internal returns (uint256) {
        Snapshot memory snapshot = votesForInitiativeSnapshots[epoch() - 1][_initiative];
        if (snapshot.finalized == 0) {
            uint256 votingThreshold = calculateVotingThreshold();
            ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
            uint256 votes = sharesToVotes(_shareRate, shareAllocation.shares);
            uint256 vetos = sharesToVotes(_shareRate, shareAllocation.vetoShares);
            // if the votes didn't meet the voting threshold then no votes qualify
            if (votes >= votingThreshold && votes >= vetos) {
                snapshot.votes = uint248(votes);
            }
            snapshot.finalized = 1;
            votesForInitiativeSnapshots[epoch() - 1][_initiative] = snapshot;
        }
        return snapshot.votes;
    }

    function registerInitiative(address _initiative) external {
        require(_initiative != address(0), "Voting: zero-address");
        require(initiativesRegistered[_initiative] == 0, "Voting: initiative-already-registered");
        initiativesRegistered[_initiative] = block.timestamp;
    }

    function unregisterInitiative(address _initiative) external {
        uint256 shareRate = stakingV2.currentShareRate();
        _snapshotVotes(shareRate);
        uint256 votesForInitiative = _snapshotVotesForInitiative(shareRate, _initiative);
        ShareAllocation memory shareAllocation = sharesAllocatedToInitiative[_initiative];
        uint256 vetosForInitiative = sharesToVotes(shareRate, shareAllocation.vetoShares);

        // unregister initiative if it didn't receive enough votes in 4 subsequent epochs
        require(
            (
                votesForInitiative == 0 && votesForInitiativeSnapshots[epoch() - 2][_initiative].votes == 0
                    && votesForInitiativeSnapshots[epoch() - 3][_initiative].votes == 0
                    && votesForInitiativeSnapshots[epoch() - 4][_initiative].votes == 0
            ) || vetosForInitiative > votesForInitiative && vetosForInitiative > calculateVotingThreshold() * 3,
            "Voting: cannot-unregister-initiative"
        );

        delete initiativesRegistered[_initiative];
    }

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
                        qualifyingShares -= sharesAllocatedToInitiative_.shares - uint256(-deltaShares);
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
    function distributeToInitiative(address _initiative, address _token) external {
        require(distributeToInitiativeInEpoch[epoch() - 1][_initiative] == false, "Voting: already-distributed");

        uint256 shareRate = stakingV2.currentShareRate();
        uint256 votesForInitiative = _snapshotVotesForInitiative(shareRate, _initiative);
        uint256 votes = _snapshotVotes(shareRate);
        uint256 claim = votesForInitiative * accruedInEpoch[epoch() - 1][_token] / votes;

        distributeToInitiativeInEpoch[epoch() - 1][_initiative] = true;
        IERC20(_token).safeTransfer(_initiative, claim);
    }

    function deposit(address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        accruedInEpoch[epoch()][_token] += _amount;
    }
}
