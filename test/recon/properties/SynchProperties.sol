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
    // Ensure that a non zero vote uses the user latest TS
    // This ensures that the math is correct in removal and addition
    function property_initiative_ts_matches_user_when_non_zero() public {
        // For all strategies
        for (uint256 i; i < deployedInitiatives.length; i++) {
            for (uint256 j; j < users.length; j++) {
                (uint88 votes, , uint16 epoch) = governance.lqtyAllocatedByUserToInitiative(users[j], deployedInitiatives[i]);

                // Grab epoch from initiative
                (uint88 lqtyAllocatedByUserAtEpoch, uint32 ts) =
                    IBribeInitiative(deployedInitiatives[i]).lqtyAllocatedByUserAtEpoch(users[j], epoch);

                // Check that TS matches (only for votes)
                eq(lqtyAllocatedByUserAtEpoch, votes, "Votes must match at all times");

                if(votes != 0) {
                    // if we're voting and the votes are different from 0
                    // then we check user TS
                    (, uint32 averageStakingTimestamp) = governance.userStates(users[j]);

                    eq(averageStakingTimestamp, ts, "Timestamp must be most recent when it's non zero");
                } else {
                    // NOTE: If votes are zero the TS is passed, but it is not a useful value
                    // This is left here as a note for the reviewer
                }
            }
        }

    }


}