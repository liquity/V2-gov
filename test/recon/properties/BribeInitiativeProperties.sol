
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {IBribeInitiative} from "../../../src/interfaces/IBribeInitiative.sol";

abstract contract BribeInitiativeProperties is BeforeAfter {
    function property_BI01() public {
        uint16 currentEpoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            // if the bool switches, the user has claimed their bribe for the epoch
            if(_before.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] != _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch]) {
                // calculate user balance delta of the bribe tokens
                uint128 lqtyBalanceDelta = _after.lqtyBalance - _before.lqtyBalance;
                uint128 lusdBalanceDelta = _after.lusdBalance - _before.lusdBalance;
            
                // calculate balance delta as a percentage of the total bribe for this epoch
                (uint128 bribeBoldAmount, uint128 bribeBribeTokenAmount) = IBribeInitiative(initiative).bribeByEpoch(currentEpoch);
                uint128 lqtyPercentageOfBribe = (lqtyBalanceDelta / bribeBribeTokenAmount) * 10_000;
                uint128 lusdPercentageOfBribe = (lusdBalanceDelta / bribeBoldAmount) * 10_000;

                // Shift right by 40 bits (128 - 88) to get the 88 most significant bits
                uint88 lqtyPercentageOfBribe88 = uint88(lqtyPercentageOfBribe >> 40);
                uint88 lusdPercentageOfBribe88 = uint88(lusdPercentageOfBribe >> 40);

                // calculate user allocation percentage of total for this epoch
                (uint88 lqtyAllocatedByUserAtEpoch, ) = IBribeInitiative(initiative).lqtyAllocatedByUserAtEpoch(user, currentEpoch);
                (uint88 totalLQTYAllocatedAtEpoch, ) = IBribeInitiative(initiative).totalLQTYAllocatedByEpoch(currentEpoch);
                uint88 allocationPercentageOfTotal = (lqtyAllocatedByUserAtEpoch / totalLQTYAllocatedAtEpoch) * 10_000;

                // check that allocation percentage and received bribe percentage match
                eq(lqtyPercentageOfBribe88, allocationPercentageOfTotal, "BI-01: User should receive percentage of bribes corresponding to their allocation");
                eq(lusdPercentageOfBribe88, allocationPercentageOfTotal, "BI-01: User should receive percentage of BOLD bribes corresponding to their allocation");
            }
        }
    }

    function property_BI02() public {
        t(!claimedTwice, "B2-01: User can only claim bribes once in an epoch");
    }

    function property_BI03() public {
        uint16 currentEpoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            (uint88 lqtyAllocatedByUserAtEpoch, ) = initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
            eq(ghostLqtyAllocationByUserAtEpoch[user], lqtyAllocatedByUserAtEpoch, "BI-03: Accounting for user allocation amount is always correct");
        }
    }

    function property_BI04() public {
        uint16 currentEpoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            (uint88 totalLQTYAllocatedAtEpoch, ) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
            eq(ghostTotalAllocationAtEpoch[currentEpoch], totalLQTYAllocatedAtEpoch, "BI-04: Accounting for total allocation amount is always correct");
        }
    }

    // TODO: double check that this implementation is correct
    function property_BI05() public {
        uint16 currentEpoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            // if the bool switches, the user has claimed their bribe for the epoch
            if(_before.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] != _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch]) {
                // check that the remaining bribe amount left over is less than 100 million wei
                uint256 bribeTokenBalanceInitiative = lqty.balanceOf(initiative);
                uint256 boldTokenBalanceInitiative = lusd.balanceOf(initiative);

                lte(bribeTokenBalanceInitiative, 1e8, "BI-05: Bribe token dust amount remaining after claiming should be less than 100 million wei");
                lte(boldTokenBalanceInitiative, 1e8, "BI-05: Bold token dust amount remaining after claiming should be less than 100 million wei");
            }
        }
    }

    function property_BI06() public {
        // using ghost tracking for successful bribe deposits
        uint16 currentEpoch = governance.epoch();

        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            IBribeInitiative.Bribe memory bribe = ghostBribeByEpoch[initiative][currentEpoch];
            (uint128 boldAmount, uint128 bribeTokenAmount) = IBribeInitiative(initiative).bribeByEpoch(currentEpoch);
            eq(bribe.boldAmount, boldAmount, "BI-06: Accounting for bold amount in bribe for an epoch is always correct");
            eq(bribe.bribeTokenAmount, bribeTokenAmount, "BI-06: Accounting for bold amount in bribe for an epoch is always correct");
        }
    }

    function property_BI07() public { 
        uint16 currentEpoch = governance.epoch();

        // sum user allocations for an epoch
        // check that this matches the total allocation for the epoch
        for(uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            uint88 sumLqtyAllocated;
            for(uint8 j; j < users.length; j++) {
                address user = users[j];
                (uint88 lqtyAllocated, ) = initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
                sumLqtyAllocated += lqtyAllocated;
            }
            (uint88 totalLQTYAllocated, ) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
            eq(sumLqtyAllocated, totalLQTYAllocated, "BI-07: Sum of user LQTY allocations for an epoch != total LQTY allocation for the epoch");
        }
    }

    function property_BI08() public { 
        // users can only claim for epoch that has already passed
        uint16 checkEpoch = governance.epoch() - 1;

        // use lqtyAllocatedByUserAtEpoch to determine if a user is allocated for an epoch
        // use claimedBribeForInitiativeAtEpoch to determine if user has claimed bribe for an epoch (would require the value changing from false -> true)
        for(uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for(uint8 j; j < users.length; j++) {
                (uint88 lqtyAllocated, ) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);

                // check that user had no lqtyAllocated for the epoch and therefore shouldn't be able to claim for it
                if(lqtyAllocated == 0) {
                    // since bool could only possibly change from false -> true, just check that it's the same before and after
                    bool claimedBefore = _before.claimedBribeForInitiativeAtEpoch[address(initiative)][users[j]][checkEpoch];
                    bool claimedAfter = _before.claimedBribeForInitiativeAtEpoch[address(initiative)][users[j]][checkEpoch];
                    t(claimedBefore == claimedAfter, "BI-08: User cannot claim bribes for an epoch in which they are not allocated");
                }
            }
        }
    }

}