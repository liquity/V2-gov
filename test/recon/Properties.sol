
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {

    function property_BI02() public {
        t(!claimedTwice, "B2-01: User can only claim bribes once in an epoch");
    }

    function property_BI03() public {
        uint16 currentEpoch = governance.epoch();
        uint88 lqtyAllocatedByUserAtEpoch = initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
        eq(ghostLqtyAllocationByUserAtEpoch[user].items[currentEpoch].value, lqtyAllocatedByUserAtEpoch, "BI-03: Accounting for user allocation amount is always correct");
    }

    function property_BI04() public {
        uint16 currentEpoch = governance.epoch();
        uint88 totalLQTYAllocatedAtEpoch = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
        eq(ghostTotalAllocationAtEpoch[currentEpoch], totalLQTYAllocatedAtEpoch, "BI-04: Accounting for total allocation amount is always correct");
    }
}
