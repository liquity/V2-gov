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
    


}