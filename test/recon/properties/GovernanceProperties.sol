// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {MockStakingV1} from "test/mocks/MockStakingV1.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract GovernanceProperties is BeforeAfter {
    

    /// A Initiative cannot change in status
    /// Except for being unregistered
    ///     Or claiming rewards
    function property_GV01() public {
        // first check that epoch hasn't changed after the operation
        if(_before.epoch == _after.epoch) {
            // loop through the initiatives and check that their status hasn't changed
            for(uint8 i; i < deployedInitiatives.length; i++) {
                address initiative = deployedInitiatives[i];

                // Hardcoded Allowed FSM
                if(_before.initiativeStatus[initiative] == Governance.InitiativeStatus.UNREGISTERABLE) {
                    // ALLOW TO SET DISABLE
                    if(_after.initiativeStatus[initiative] == Governance.InitiativeStatus.DISABLED) {
                        return;
                    }
                }

                if(_before.initiativeStatus[initiative] == Governance.InitiativeStatus.CLAIMABLE) {
                    // ALLOW TO CLAIM
                    if(_after.initiativeStatus[initiative] == Governance.InitiativeStatus.CLAIMED) {
                        return;
                    }
                }
                
                if(_before.initiativeStatus[initiative] == Governance.InitiativeStatus.NONEXISTENT) {
                    // Registered -> SKIP is ok
                    if(_after.initiativeStatus[initiative] == Governance.InitiativeStatus.COOLDOWN) {
                        return;
                    }
                }

                eq(uint256(_before.initiativeStatus[initiative]), uint256(_after.initiativeStatus[initiative]), "GV-01: Initiative state should only return one state per epoch");
            }
        }
    }


    function property_stake_and_votes_cannot_be_abused() public {
        // User stakes
        // User allocated

        // allocated is always <= stakes
        for(uint256 i; i < users.length; i++) {
            // Only sum up user votes
            address userProxyAddress = governance.deriveUserProxyAddress(users[i]);
            uint256 stake = MockStakingV1(stakingV1).stakes(userProxyAddress);
            
            (uint88 user_allocatedLQTY, ) = governance.userStates(users[i]);
            lte(user_allocatedLQTY, stake, "User can never allocated more than stake"); 
        }
        
    }

    // View vs non view must have same results
    function property_viewTotalVotesAndStateEquivalency() public {
        for(uint8 i; i < deployedInitiatives.length; i++) {
            (IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot_view, , bool shouldUpdate) = governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);
            (, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot) = governance.snapshotVotesForInitiative(deployedInitiatives[i]);

            eq(initiativeSnapshot_view.votes, initiativeVoteSnapshot.votes, "votes");
            eq(initiativeSnapshot_view.forEpoch, initiativeVoteSnapshot.forEpoch, "forEpoch");
            eq(initiativeSnapshot_view.lastCountedEpoch, initiativeVoteSnapshot.lastCountedEpoch, "lastCountedEpoch");
            eq(initiativeSnapshot_view.vetos, initiativeVoteSnapshot.vetos, "vetos");
        }
    }

    function property_viewCalculateVotingThreshold() public {
        (, , bool shouldUpdate) = governance.getTotalVotesAndState();

        if(!shouldUpdate) {
            // If it's already synched it must match
            uint256 latestKnownThreshold = governance.getLatestVotingThreshold();
            uint256 calculated = governance.calculateVotingThreshold();
            eq(latestKnownThreshold, calculated, "match");
        }
    }

    // Function sound total math

    // NOTE: Global vs USer vs Initiative requires changes
    // User is tracking votes and vetos together
    // Whereas Votes and Initiatives only track Votes
    /// The Sum of LQTY allocated by Users matches the global state
    // NOTE: Sum of positive votes
    function property_sum_of_lqty_global_user_matches() public {
        // Get state
        // Get all users
        // Sum up all voted users
        // Total must match
        (
            uint88 totalCountedLQTY, 
            // uint32 after_user_countedVoteLQTYAverageTimestamp // TODO: How do we do this?
        ) = governance.globalState();

        uint256 totalUserCountedLQTY;
        for(uint256 i; i < users.length; i++) {
            // Only sum up user votes
            (uint88 user_voteLQTY, ) = _getAllUserAllocations(users[i]);
            totalUserCountedLQTY += user_voteLQTY;
        }

        eq(totalCountedLQTY, totalUserCountedLQTY, "Global vs SUM(Users_lqty) must match");
    }
    
    /// The Sum of LQTY allocated to Initiatives matches the Sum of LQTY allocated by users
    function property_sum_of_lqty_initiative_user_matches() public {
        // Get Initiatives
        // Get all users
        // Sum up all voted users & initiatives
        // Total must match
        uint256 totalInitiativesCountedVoteLQTY;
        uint256 totalInitiativesCountedVetoLQTY;
        for(uint256 i; i < deployedInitiatives.length; i++) {
            (
                uint88 voteLQTY,
                uint88 vetoLQTY,
                ,
                ,
                
            ) = governance.initiativeStates(deployedInitiatives[i]);
            totalInitiativesCountedVoteLQTY += voteLQTY;
            totalInitiativesCountedVetoLQTY += vetoLQTY;
        }


        uint256 totalUserCountedLQTY;
        for(uint256 i; i < users.length; i++) {
            (uint88 user_allocatedLQTY, ) = governance.userStates(users[i]);
            totalUserCountedLQTY += user_allocatedLQTY;
        }

        eq(totalInitiativesCountedVoteLQTY + totalInitiativesCountedVetoLQTY, totalUserCountedLQTY, "SUM(Initiatives_lqty) vs SUM(Users_lqty) must match");
    }

    // TODO: also `lqtyAllocatedByUserToInitiative`
    // For each user, for each initiative, allocation is correct
    function property_sum_of_user_initiative_allocations() public {
        for(uint256 x; x < deployedInitiatives.length; x++) {
            (
                uint88 initiative_voteLQTY,
                uint88 initiative_vetoLQTY,
                ,
                ,
                
            ) = governance.initiativeStates(deployedInitiatives[x]);


            // Grab all users and sum up their participations
            uint256 totalUserVotes;
            uint256 totalUserVetos;
            for(uint256 y; y < users.length; y++) {
                (uint88 vote_allocated, uint88 veto_allocated) = _getUserAllocation(users[y], deployedInitiatives[x]);
                totalUserVotes += vote_allocated;
                totalUserVetos += veto_allocated;
            }

            eq(initiative_voteLQTY, totalUserVotes, "Sum of users, matches initiative votes");
            eq(initiative_vetoLQTY, totalUserVetos, "Sum of users, matches initiative vetos");
        }
    }

    // sum of voting power for users that allocated to an initiative == the voting power of the initiative
    /// TODO ??
    function property_sum_of_user_voting_weights() public {
        // loop through all users 
        // - calculate user voting weight for the given timestamp
        // - sum user voting weights for the given epoch
        // - compare with the voting weight of the initiative for the epoch for the same timestamp
        
        for(uint256 i; i < deployedInitiatives.length; i++) {
            uint240 userWeightAccumulatorForInitiative;
            for(uint256 j; j < users.length; j++) {
                (uint88 userVoteLQTY,,) = governance.lqtyAllocatedByUserToInitiative(users[j], deployedInitiatives[i]);
                // TODO: double check that okay to use this average timestamp
                (, uint32 averageStakingTimestamp) = governance.userStates(users[j]);
                // add the weight calculated for each user's allocation to the accumulator
                userWeightAccumulatorForInitiative += governance.lqtyToVotes(userVoteLQTY, block.timestamp, averageStakingTimestamp);
            }

            (uint88 initiativeVoteLQTY,, uint32 initiativeAverageStakingTimestampVoteLQTY,,) = governance.initiativeStates(deployedInitiatives[i]);
            uint240 initiativeWeight = governance.lqtyToVotes(initiativeVoteLQTY, block.timestamp, initiativeAverageStakingTimestampVoteLQTY);
            eq(initiativeWeight, userWeightAccumulatorForInitiative, "initiative voting weights and user's allocated weight differs for initiative");
        }
    }


    function property_sum_of_initatives_matches_total_votes() public {
        // Sum up all initiatives
        // Compare to total votes
        (IGovernance.VoteSnapshot memory snapshot, IGovernance.GlobalState memory state, bool shouldUpdate) = governance.getTotalVotesAndState();
        
        uint256 initiativeVotesSum;
        for(uint256 i; i < deployedInitiatives.length; i++) {
            (IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot, IGovernance.InitiativeState memory initiativeState, bool shouldUpdate) = governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(deployedInitiatives[i]);

            if(status != Governance.InitiativeStatus.DISABLED) {
                // FIX: Only count total if initiative is not disabled
                initiativeVotesSum += initiativeSnapshot.votes;
            }
        }

        eq(snapshot.votes, initiativeVotesSum, "Sum of votes matches");
    }


    function check_skip_consistecy(uint8 initiativeIndex) public {
        // If a initiative has no votes
        // In the next epoch it can either be SKIP or UNREGISTERABLE
        address initiative = _getDeployedInitiative(initiativeIndex);

        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
        if(status == Governance.InitiativeStatus.SKIP) {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());
            (Governance.InitiativeStatus newStatus,,) = governance.getInitiativeState(initiative);
            t(uint256(status) == uint256(newStatus) || uint256(newStatus) == uint256(Governance.InitiativeStatus.UNREGISTERABLE) || uint256(newStatus) == uint256(Governance.InitiativeStatus.CLAIMABLE), "Either SKIP or UNREGISTERABLE or CLAIMABLE");
        }
    }

    // TOFIX: The property breaks because you can vote on a UNREGISTERABLE
    // Hence it can become Claimable next week
    function check_unregisterable_consistecy(uint8 initiativeIndex) public {
        // If a initiative has no votes and is UNREGISTERABLE
        // In the next epoch it will remain UNREGISTERABLE
        address initiative = _getDeployedInitiative(initiativeIndex);

        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
        if(status == Governance.InitiativeStatus.UNREGISTERABLE) {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());
            (Governance.InitiativeStatus newStatus,,) = governance.getInitiativeState(initiative);
            t(uint256(status) == uint256(newStatus) || uint256(newStatus) == uint256(Governance.InitiativeStatus.CLAIMABLE), "UNREGISTERABLE must remain UNREGISTERABLE unless voted on but can become CLAIMABLE due to relaxed checks in allocateLQTY");
        }

    }


    function _getUserAllocation(address theUser, address initiative) internal view returns (uint88 votes, uint88 vetos) {
        (votes, vetos, ) = governance.lqtyAllocatedByUserToInitiative(theUser, initiative);
    }
    function _getAllUserAllocations(address theUser) internal view returns (uint88 votes, uint88 vetos) {
        for(uint256 i; i < deployedInitiatives.length; i++) {
            (uint88 allocVotes, uint88 allocVetos, ) = governance.lqtyAllocatedByUserToInitiative(theUser, deployedInitiatives[i]);
            votes += allocVotes;
            vetos += allocVetos;
        }
    }
}