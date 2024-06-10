// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {StakingV2, WAD} from "./StakingV2.sol";

uint256 constant ONE_WEEK = 604800;

contract Voting {
    uint256 public immutable deploymentTimestamp = block.timestamp;

    StakingV2 public stakingV2;

    mapping(uint256 => mapping(address => uint256)) public accruedInEpoch;
    mapping(uint256 => mapping(address => bool)) public distributeToInitiativeInEpoch;

    struct Snapshot {
        uint256 votes;
        bool finalized;
    }

    mapping(uint256 => Snapshot) public qualifiedVotesSnapshots;
    mapping(uint256 => mapping(address => Snapshot)) qualifiedVotesForInitiativeSnapshots;

    uint256 public qualifiedSharesAllocated;
    mapping(address => uint256) public sharesAllocatedByUser;
    mapping(address => uint256) public sharesAllocatedForInitiative;
    mapping(address => mapping(address => uint256)) public sharesAllocatedByUserForInitiative;

    struct Initiative {
        address proposer;
    }

    mapping(address => Initiative) public initiatives;

    constructor(address stakingV2_) {
        stakingV2 = StakingV2(stakingV2_);
    }

    // store last epoch
    function epoch() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) / ONE_WEEK) + 1;
    }

    // Voting power statically increases over time starting from 0 at time of share issuance
    function sharesToVotes(uint256 shareRate, uint256 shares) public pure returns (uint256) {
        uint256 weightedShares = shares * shareRate / WAD;
        return weightedShares - shares;
    }

    // Voting threshold is 4% of total shares allocated in the previous epoch
    function calculateVotingThreshold() public view returns (uint256) {
        return qualifiedVotesSnapshots[epoch() - 1].votes * 0.04e18 / WAD;
    }

    function _snapshotQualifiedSharesAllocated(uint256 shareRate) internal returns (uint256) {
        Snapshot memory snapshot = qualifiedVotesSnapshots[epoch() - 1];
        if (!snapshot.finalized) {
            snapshot.votes = sharesToVotes(shareRate, qualifiedSharesAllocated);
            snapshot.finalized = true;
            qualifiedVotesSnapshots[epoch() - 1] = snapshot;
        }
        return snapshot.votes;
    }

    function _snapshotSharesAllocatedForInitiative(address initiative, uint256 shareRate) internal returns (uint256) {
        Snapshot memory snapshot = qualifiedVotesForInitiativeSnapshots[epoch() - 1][initiative];
        if (!snapshot.finalized) {
            uint256 votes = sharesToVotes(shareRate, sharesAllocatedForInitiative[initiative]);
            // if the votes didn't meet the voting threshold then no votes qualify
            if (votes >= calculateVotingThreshold()) {
                snapshot.votes = votes;
            }
            snapshot.finalized = true;
            qualifiedVotesForInitiativeSnapshots[epoch() - 1][initiative] = snapshot;
        }
        return snapshot.votes;
    }

    function registerInitiative(address initiative) external {
        require(initiative != address(0), "Voting: zero-address");
        require(initiatives[initiative].proposer == address(0), "Voting: initiative-already-registered");
        initiatives[initiative] = Initiative(msg.sender);
    }

    // force user to with 100% of shares, pass array of initiatives
    function allocateShares(address initiative, uint256 shares) external {
        uint256 shareRate = stakingV2.currentShareRate();
        _snapshotQualifiedSharesAllocated(shareRate);
        _snapshotSharesAllocatedForInitiative(initiative, shareRate);

        uint256 sharesAllocatedByUser_ = sharesAllocatedByUser[msg.sender];
        require(stakingV2.sharesByUser(msg.sender) >= sharesAllocatedByUser_ + shares, "Voting: insufficient-shares");

        sharesAllocatedByUser[msg.sender] = sharesAllocatedByUser_ + shares;
        uint256 sharesAllocatedByUserForInitiative_ = sharesAllocatedByUserForInitiative[msg.sender][initiative];
        sharesAllocatedByUserForInitiative[msg.sender][initiative] = sharesAllocatedByUserForInitiative_ + shares;
        sharesAllocatedForInitiative[initiative] += shares;

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 votesAllocatedForInitiative = sharesToVotes(shareRate, sharesAllocatedByUserForInitiative_);
        if (votesAllocatedForInitiative + sharesToVotes(shareRate, shares) >= votingThreshold) {
            if (votesAllocatedForInitiative < votingThreshold) {
                qualifiedSharesAllocated += sharesAllocatedByUserForInitiative_ + shares;
            } else {
                qualifiedSharesAllocated += shares;
            }
        }
    }

    function deallocateShares(address initiative, uint256 shares) external {
        uint256 shareRate = stakingV2.currentShareRate();

        _snapshotQualifiedSharesAllocated(shareRate);
        _snapshotSharesAllocatedForInitiative(initiative, shareRate);

        uint256 sharesAllocatedByUserForInitiative_ = sharesAllocatedByUserForInitiative[msg.sender][initiative];
        require(shares <= sharesAllocatedByUserForInitiative_, "Voting: gt-shares-allocated");

        sharesAllocatedByUser[msg.sender] -= shares;
        sharesAllocatedByUserForInitiative[msg.sender][initiative] = sharesAllocatedByUserForInitiative_ - shares;
        sharesAllocatedForInitiative[initiative] -= shares;

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 votesAllocatedForInitiative = sharesToVotes(shareRate, sharesAllocatedByUserForInitiative_);
        if (votesAllocatedForInitiative >= votingThreshold) {
            if (votesAllocatedForInitiative - sharesToVotes(shareRate, shares) >= votingThreshold) {
                qualifiedSharesAllocated -= shares;
            } else {
                qualifiedSharesAllocated -= sharesAllocatedByUserForInitiative_ + shares;
            }
        }
    }

    // split accrued funds according to votes received between all initiatives
    function distributeToInitiative(address initiative, address token) external {
        uint256 shareRate = stakingV2.currentShareRate();
        uint256 qualifiedVotes = _snapshotQualifiedSharesAllocated(shareRate);
        uint256 qualifiedVotesForInitiative = _snapshotSharesAllocatedForInitiative(initiative, shareRate);
        uint256 claim = qualifiedVotesForInitiative * accruedInEpoch[epoch() - 1][token] / qualifiedVotes;
        distributeToInitiativeInEpoch[epoch() - 1][initiative] = true;
        IERC20(token).transfer(initiative, claim);
    }

    function accrue(address token) external {}
}
