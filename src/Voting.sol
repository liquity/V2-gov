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
        uint256 votesAllocated;
        bool finalized;
    }

    mapping(uint256 => Snapshot) public votesAllocatedSnapshots;
    mapping(uint256 => mapping(address => Snapshot)) votesAllocatedForInitiativeSnapshots;

    uint256 public votesAllocated;
    mapping(address => uint256) public votesAllocatedByUser;
    mapping(address => uint256) public votesAllocatedForInitiative;
    mapping(address => mapping(address => uint256)) public votesAllocatedByUserForInitiative;

    struct Initiative {
        address proposer;
    }

    mapping(address => Initiative) public initiatives;

    constructor(address stakingV2_) {
        stakingV2 = StakingV2(stakingV2_);
    }

    function epoch() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) / ONE_WEEK) + 1;
    }

    function registerInitiative(address initiative) public {
        require(initiative != address(0), "Voting: zero-address");
        require(initiatives[initiative].proposer == address(0), "Voting: initiative-already-registered");
        initiatives[initiative] = Initiative(msg.sender);
    }

    // Voting power statically increases over time starting from 0 at time of share issuance
    function votingPower(address user) public view returns (uint256) {
        uint256 shares = stakingV2.sharesByUser(user);
        uint256 weightedShares = shares * stakingV2.currentShareRate() / WAD;
        return weightedShares - shares;
    }

    function snapshotVotesAllocated() internal returns (uint256) {
        Snapshot memory snapshot = votesAllocatedSnapshots[epoch() - 1];
        if (!snapshot.finalized) {
            snapshot.votesAllocated = votesAllocated;
            snapshot.finalized = true;
            votesAllocatedSnapshots[epoch() - 1] = snapshot;
        }
        return snapshot.votesAllocated;
    }

    function snapshotVotesAllocatedForInitiative(address initiative) internal returns (uint256) {
        Snapshot memory snapshot = votesAllocatedForInitiativeSnapshots[epoch() - 1][initiative];
        if (!snapshot.finalized) {
            snapshot.votesAllocated = votesAllocatedForInitiative[initiative];
            snapshot.finalized = true;
            votesAllocatedForInitiativeSnapshots[epoch() - 1][initiative] = snapshot;
        }
        return snapshot.votesAllocated;
    }

    // Voting threshold is 4% of total votes allocated in the previous epoch
    function calculateVotingThreshold() public view returns (uint256) {
        return votesAllocatedSnapshots[epoch() - 1].votesAllocated * 0.04e18 / WAD;
    }

    function vote(address initiative, uint256 votes) public {
        snapshotVotesAllocated();
        snapshotVotesAllocatedForInitiative(initiative);

        uint256 _votesAllocatedByUser = votesAllocatedByUser[msg.sender];
        require(votingPower(msg.sender) >= _votesAllocatedByUser + votes, "Voting: insufficient-voting-power");

        votesAllocatedByUser[msg.sender] = _votesAllocatedByUser + votes;
        uint256 _votesAllocatedByUserForInitiative = votesAllocatedByUserForInitiative[msg.sender][initiative];
        votesAllocatedByUserForInitiative[msg.sender][initiative] = _votesAllocatedByUserForInitiative + votes;
        votesAllocatedForInitiative[initiative] += votes;

        uint256 votingThreshold = calculateVotingThreshold();
        if (_votesAllocatedByUserForInitiative + votes >= votingThreshold) {
            if (_votesAllocatedByUserForInitiative < votingThreshold) {
                votesAllocated += _votesAllocatedByUserForInitiative + votes;
            } else {
                votesAllocated += votes;
            }
        }
    }

    function unvote(address initiative, uint256 votes) public {
        snapshotVotesAllocated();
        snapshotVotesAllocatedForInitiative(initiative);

        uint256 _votesAllocatedByUserForInitiative = votesAllocatedByUserForInitiative[msg.sender][initiative];
        require(votes <= _votesAllocatedByUserForInitiative, "Voting: gt-votes-allocated");

        votesAllocatedByUser[msg.sender] -= votes;
        votesAllocatedByUserForInitiative[msg.sender][initiative] = _votesAllocatedByUserForInitiative - votes;
        votesAllocatedForInitiative[initiative] -= votes;
        votesAllocated -= votes;

        uint256 votingThreshold = calculateVotingThreshold();
        if (_votesAllocatedByUserForInitiative >= votingThreshold) {
            if (_votesAllocatedByUserForInitiative - votes >= votingThreshold) {
                votesAllocated -= votes;
            } else {
                votesAllocated -= _votesAllocatedByUserForInitiative + votes;
            }
        }
    }

    // split accrued funds according to votes received between all initiatives
    function distributeToInitiative(address initiative, address token) public {
        uint256 _votesAllocated = snapshotVotesAllocated();
        uint256 _votesAllocatedForInitiative = snapshotVotesAllocatedForInitiative(initiative);
        uint256 claim = _votesAllocatedForInitiative * accruedInEpoch[epoch() - 1][token] / _votesAllocated;
        distributeToInitiativeInEpoch[epoch() - 1][initiative] = true;
        IERC20(token).transfer(initiative, claim);
    }
}
