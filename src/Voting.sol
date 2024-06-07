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

    function registerInitiative(address initiative) public {
        require(initiative != address(0), "Voting: zero-address");
        require(initiatives[initiative].proposer == address(0), "Voting: initiative-already-registered");
        initiatives[initiative] = Initiative(msg.sender);
    }

    // Voting power statically increases over time starting from 0 at time of share issuance
    function sharesToVotes(uint256 shareRate, uint256 shares) public pure returns (uint256) {
        uint256 weightedShares = shares * shareRate / WAD;
        return weightedShares - shares;
    }

    function snapshotQualifiedSharesAllocated(uint256 shareRate) internal returns (uint256) {
        Snapshot memory snapshot = qualifiedVotesSnapshots[epoch() - 1];
        if (!snapshot.finalized) {
            uint256 votes = sharesToVotes(shareRate, qualifiedSharesAllocated);
            if (votes >= calculateVotingThreshold()) {
                snapshot.votes = sharesToVotes(shareRate, qualifiedSharesAllocated);
            }
            snapshot.finalized = true;
            qualifiedVotesSnapshots[epoch() - 1] = snapshot;
        }
        return snapshot.votes;
    }

    function snapshotSharesAllocatedForInitiative(address initiative, uint256 shareRate) internal returns (uint256) {
        Snapshot memory snapshot = qualifiedVotesForInitiativeSnapshots[epoch() - 1][initiative];
        if (!snapshot.finalized) {
            uint256 votes = sharesToVotes(shareRate, sharesAllocatedForInitiative[initiative]);
            if (votes >= calculateVotingThreshold()) {
                snapshot.votes = sharesToVotes(shareRate, qualifiedSharesAllocated);
            }
            snapshot.finalized = true;
            qualifiedVotesForInitiativeSnapshots[epoch() - 1][initiative] = snapshot;
        }
        return snapshot.votes;
    }

    // Voting threshold is 4% of total shares allocated in the previous epoch
    function calculateVotingThreshold() public view returns (uint256) {
        return qualifiedVotesSnapshots[epoch() - 1].votes * 0.04e18 / WAD;
    }

    // force user to with 100% of shares, pass array of initiatives
    function allocateShares(address initiative, uint256 shares) public {
        uint256 shareRate = stakingV2.currentShareRate();
        snapshotQualifiedSharesAllocated(shareRate);
        snapshotSharesAllocatedForInitiative(initiative, shareRate);

        uint256 _sharesAllocatedByUser = sharesAllocatedByUser[msg.sender];
        require(stakingV2.sharesByUser(msg.sender) >= _sharesAllocatedByUser + shares, "Voting: insufficient-shares");

        sharesAllocatedByUser[msg.sender] = _sharesAllocatedByUser + shares;
        uint256 _sharesAllocatedByUserForInitiative = sharesAllocatedByUserForInitiative[msg.sender][initiative];
        sharesAllocatedByUserForInitiative[msg.sender][initiative] = _sharesAllocatedByUserForInitiative + shares;
        sharesAllocatedForInitiative[initiative] += shares;

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 votesAllocatedForInitiative = sharesToVotes(shareRate, _sharesAllocatedByUserForInitiative);
        if (votesAllocatedForInitiative + sharesToVotes(shareRate, shares) >= votingThreshold) {
            if (votesAllocatedForInitiative < votingThreshold) {
                qualifiedSharesAllocated += _sharesAllocatedByUserForInitiative + shares;
            } else {
                qualifiedSharesAllocated += shares;
            }
        }
    }

    function deallocateShares(address initiative, uint256 shares) public {
        uint256 shareRate = stakingV2.currentShareRate();

        snapshotQualifiedSharesAllocated(shareRate);
        snapshotSharesAllocatedForInitiative(initiative, shareRate);

        uint256 _sharesAllocatedByUserForInitiative = sharesAllocatedByUserForInitiative[msg.sender][initiative];
        require(shares <= _sharesAllocatedByUserForInitiative, "Voting: gt-shares-allocated");

        sharesAllocatedByUser[msg.sender] -= shares;
        sharesAllocatedByUserForInitiative[msg.sender][initiative] = _sharesAllocatedByUserForInitiative - shares;
        sharesAllocatedForInitiative[initiative] -= shares;
        // sharesAllocated -= shares;

        uint256 votingThreshold = calculateVotingThreshold();
        uint256 votesAllocatedForInitiative = sharesToVotes(shareRate, _sharesAllocatedByUserForInitiative);
        if (votesAllocatedForInitiative >= votingThreshold) {
            if (votesAllocatedForInitiative - sharesToVotes(shareRate, shares) >= votingThreshold) {
                qualifiedSharesAllocated -= shares;
            } else {
                qualifiedSharesAllocated -= _sharesAllocatedByUserForInitiative + shares;
            }
        }
    }

    // split accrued funds according to votes received between all initiatives
    function distributeToInitiative(address initiative, address token) public {
        uint256 shareRate = stakingV2.currentShareRate();
        uint256 qualifiedVotes = snapshotQualifiedSharesAllocated(shareRate);
        uint256 qualifiedVotesForInitiative = snapshotSharesAllocatedForInitiative(initiative, shareRate);
        uint256 claim = qualifiedVotesForInitiative * accruedInEpoch[epoch() - 1][token] / qualifiedVotes;
        distributeToInitiativeInEpoch[epoch() - 1][initiative] = true;
        IERC20(token).transfer(initiative, claim);
    }
}
