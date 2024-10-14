
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "./BeforeAfter.sol";

abstract contract Properties is BeforeAfter {
    function property_BI01() public {
        uint16 currentEpoch = governance.epoch();
        // if the bool switches, the user has claimed their bribe for the epoch
        if(_before.claimedBribeAtEpoch[user][currentEpoch] != _after.claimedBribeAtEpoch[user][currentEpoch]) {
            // calculate user balance delta of the bribe tokens
            uint128 lqtyBalanceDelta = _after.lqtyBalance - _before.lqtyBalance;
            uint128 lusdBalanceDelta = _after.lusdBalance - _before.lusdBalance;
           
            // calculate balance delta as a percentage of the total bribe for this epoch
            (uint128 bribeBoldAmount, uint128 bribeBribeTokenAmount) = initiative.bribeByEpoch(currentEpoch);
            uint128 lqtyPercentageOfBribe = (lqtyBalanceDelta / bribeBribeTokenAmount) * 10_000;
            uint128 lusdPercentageOfBribe = (lusdBalanceDelta / bribeBoldAmount) * 10_000;

             // Shift right by 40 bits (128 - 88) to get the 88 most significant bits
            uint88 lqtyPercentageOfBribe88 = uint88(lqtyPercentageOfBribe >> 40);
            uint88 lusdPercentageOfBribe88 = uint88(lusdPercentageOfBribe >> 40);

            // calculate user allocation percentage of total for this epoch
            uint88 lqtyAllocatedByUserAtEpoch = initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
            uint88 totalLQTYAllocatedAtEpoch = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
            uint88 allocationPercentageOfTotal = (lqtyAllocatedByUserAtEpoch / totalLQTYAllocatedAtEpoch) * 10_000;

            // check that allocation percentage and received bribe percentage match
            eq(lqtyPercentageOfBribe88, allocationPercentageOfTotal, "BI-01: User should receive percentage of bribes corresponding to their allocation");
            eq(lusdPercentageOfBribe88, allocationPercentageOfTotal, "BI-01: User should receive percentage of BOLD bribes corresponding to their allocation");
        }
    }

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
