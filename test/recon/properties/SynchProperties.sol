// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";

abstract contract SynchProperties is BeforeAfter {
    // Properties that ensure that the states are synched
    // Go through each initiative
    // Go through each user
    // Ensure that a non zero vote uses the user latest offset
    // This ensures that the math is correct in removal and addition
    // TODO: check whether this property really holds for offsets, since they are sums
    function property_initiative_offset_matches_user_when_non_zero() public {
        // For all strategies
        for (uint256 i; i < deployedInitiatives.length; i++) {
            for (uint256 j; j < users.length; j++) {
                (uint256 votes,,,, uint256 epoch) =
                    governance.lqtyAllocatedByUserToInitiative(users[j], deployedInitiatives[i]);

                // Grab epoch from initiative
                (uint256 lqtyAllocatedByUserAtEpoch, uint256 allocOffset) =
                    IBribeInitiative(deployedInitiatives[i]).lqtyAllocatedByUserAtEpoch(users[j], epoch);

                // Check that votes match
                eq(lqtyAllocatedByUserAtEpoch, votes, "Votes must match at all times");

                if (votes != 0) {
                    // if we're voting and the votes are different from 0
                    // then we check user offset
                    (,,, uint256 allocatedOffset) = governance.userStates(users[j]);

                    eq(allocatedOffset, allocOffset, "Offsets must match");
                } else {
                    // NOTE: If votes are zero the offset is zero
                }
            }
        }
    }
}
