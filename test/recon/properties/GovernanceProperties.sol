// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";

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
        for(uint256 i; i < deployedInitiatives.length; i++) {
            (
                uint88 initiative_voteLQTY,
                uint88 initiative_vetoLQTY,
                ,
                ,
                
            ) = governance.initiativeStates(deployedInitiatives[i]);


            // Grab all users and sum up their participations
            uint256 totalUserVotes;
            uint256 totalUserVetos;
            for(uint256 i; i < users.length; i++) {
                (uint88 vote_allocated, uint88 veto_allocated) = _getUserAllocation(users[i], deployedInitiatives[i]);
                totalUserVotes += vote_allocated;
                totalUserVetos += veto_allocated;
            }

            eq(initiative_voteLQTY, totalUserVotes + initiative_voteLQTY, "Sum of users, matches initiative votes");
            eq(initiative_vetoLQTY, totalUserVetos + initiative_vetoLQTY, "Sum of users, matches initiative vetos");
        }
    }

    // View vs non view


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