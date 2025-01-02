// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";

abstract contract TsProperties is BeforeAfter {
    // Properties that ensure that a user TS is somewhat sound

    function property_user_offset_is_always_greater_than_start() public {
        for (uint256 i; i < users.length; i++) {
            (,, uint256 user_allocatedLQTY, uint256 userAllocatedOffset) = governance.userStates(users[i]);
            if (user_allocatedLQTY > 0) {
                gte(userAllocatedOffset, magnifiedStartTS, "User ts must always be GTE than start");
            }
        }
    }

    function property_global_offset_is_always_greater_than_start() public {
        (uint256 totalCountedLQTY, uint256 globalTs) = governance.globalState();

        if (totalCountedLQTY > 0) {
            gte(globalTs, magnifiedStartTS, "Global ts must always be GTE than start");
        }
    }

    // TODO: Waiting 1 second should give 1 an extra second * WAD power
}
