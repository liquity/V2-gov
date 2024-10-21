// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {IBribeInitiative} from "../../../src/interfaces/IBribeInitiative.sol";

abstract contract BribeInitiativeProperties is BeforeAfter {
    function property_BI01() public {
        uint16 currentEpoch = governance.epoch();

        for (uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            for (uint8 j; j < users.length; j++) {
                // if the bool switches, the user has claimed their bribe for the epoch
                if (
                    _before.claimedBribeForInitiativeAtEpoch[initiative][users[j]][currentEpoch]
                        != _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch]
                ) {
                    // calculate user balance delta of the bribe tokens
                    uint128 userLqtyBalanceDelta = _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
                    uint128 userLusdBalanceDelta = _after.userLusdBalance[users[j]] - _before.userLusdBalance[users[j]];

                    // calculate balance delta as a percentage of the total bribe for this epoch
                    // this is what user DOES receive
                    (uint128 bribeBoldAmount, uint128 bribeBribeTokenAmount) =
                        IBribeInitiative(initiative).bribeByEpoch(currentEpoch);
                    uint128 lqtyPercentageOfBribe = (userLqtyBalanceDelta * 10_000) / bribeBribeTokenAmount;
                    uint128 lusdPercentageOfBribe = (userLusdBalanceDelta * 10_000) / bribeBoldAmount;

                    // Shift right by 40 bits (128 - 88) to get the 88 most significant bits for needed downcasting to compare with lqty allocations
                    uint88 lqtyPercentageOfBribe88 = uint88(lqtyPercentageOfBribe >> 40);
                    uint88 lusdPercentageOfBribe88 = uint88(lusdPercentageOfBribe >> 40);

                    // calculate user allocation percentage of total for this epoch
                    // this is what user SHOULD receive
                    (uint88 lqtyAllocatedByUserAtEpoch,) =
                        IBribeInitiative(initiative).lqtyAllocatedByUserAtEpoch(users[j], currentEpoch);
                    (uint88 totalLQTYAllocatedAtEpoch,) =
                        IBribeInitiative(initiative).totalLQTYAllocatedByEpoch(currentEpoch);
                    uint88 allocationPercentageOfTotal =
                        (lqtyAllocatedByUserAtEpoch * 10_000) / totalLQTYAllocatedAtEpoch;

                    // check that allocation percentage and received bribe percentage match
                    eq(
                        lqtyPercentageOfBribe88,
                        allocationPercentageOfTotal,
                        "BI-01: User should receive percentage of LQTY bribes corresponding to their allocation"
                    );
                    eq(
                        lusdPercentageOfBribe88,
                        allocationPercentageOfTotal,
                        "BI-01: User should receive percentage of BOLD bribes corresponding to their allocation"
                    );
                }
            }
        }
    }

    function property_BI02() public {
        t(!claimedTwice, "B2-01: User can only claim bribes once in an epoch");
    }

    function property_BI03() public {
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);

            (uint88 voteLQTY,, uint16 epoch) = governance.lqtyAllocatedByUserToInitiative(user, deployedInitiatives[i]);

            try initiative.lqtyAllocatedByUserAtEpoch(user, epoch) returns (uint88 amt, uint32) {
                eq(voteLQTY, amt, "Allocation must match");
            } catch {
                t(false, "Allocation doesn't match governance");
            }
        }
    }

    function property_BI04() public {
        uint16 currentEpoch = governance.epoch();
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);

            // NOTE: This doesn't revert in the future!
            uint88 lastKnownLQTYAlloc = _getLastLQTYAllocationKnown(initiative, currentEpoch);

            // We compare when we don't get a revert (a change happened this epoch)

            (uint88 voteLQTY,,,,) = governance.initiativeStates(deployedInitiatives[i]);

            eq(lastKnownLQTYAlloc, voteLQTY, "BI-04: Initiative Account matches governace");
        }
    }

    function _getLastLQTYAllocationKnown(IBribeInitiative initiative, uint16 targetEpoch)
        internal
        view
        returns (uint88)
    {
        uint16 mostRecentTotalEpoch = initiative.getMostRecentTotalEpoch();
        (uint88 totalLQTYAllocatedAtEpoch,) = initiative.totalLQTYAllocatedByEpoch(
            (targetEpoch < mostRecentTotalEpoch) ? targetEpoch : mostRecentTotalEpoch
        );
        return totalLQTYAllocatedAtEpoch;
    }

    function property_BI05() public {
        // users can't claim for current epoch so checking for previous
        uint16 checkEpoch = governance.epoch() - 1;

        for (uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            // for any epoch: expected balance = Bribe - claimed bribes, actual balance = bribe token balance of initiative
            // so if the delta between the expected and actual is > 0, dust is being collected

            uint256 lqtyClaimedAccumulator;
            uint256 lusdClaimedAccumulator;
            for (uint8 j; j < users.length; j++) {
                // if the bool switches, the user has claimed their bribe for the epoch
                if (
                    _before.claimedBribeForInitiativeAtEpoch[initiative][user][checkEpoch]
                        != _after.claimedBribeForInitiativeAtEpoch[initiative][user][checkEpoch]
                ) {
                    // add user claimed balance delta to the accumulator
                    lqtyClaimedAccumulator += _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
                    lusdClaimedAccumulator += _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
                }
            }

            (uint128 boldAmount, uint128 bribeTokenAmount) = IBribeInitiative(initiative).bribeByEpoch(checkEpoch);

            // shift 128 bit to the right to get the most significant bits of the accumulator (256 - 128 = 128)
            uint128 lqtyClaimedAccumulator128 = uint128(lqtyClaimedAccumulator >> 128);
            uint128 lusdClaimedAccumulator128 = uint128(lusdClaimedAccumulator >> 128);

            // find delta between bribe and claimed amount (how much should be remaining in contract)
            uint128 lusdDelta = boldAmount - lusdClaimedAccumulator128;
            uint128 lqtyDelta = bribeTokenAmount - lqtyClaimedAccumulator128;

            uint128 initiativeLusdBalance = uint128(lusd.balanceOf(initiative) >> 128);
            uint128 initiativeLqtyBalance = uint128(lqty.balanceOf(initiative) >> 128);

            lte(
                lusdDelta - initiativeLusdBalance,
                1e8,
                "BI-05: Bold token dust amount remaining after claiming should be less than 100 million wei"
            );
            lte(
                lqtyDelta - initiativeLqtyBalance,
                1e8,
                "BI-05: Bribe token dust amount remaining after claiming should be less than 100 million wei"
            );
        }
    }

    function property_BI06() public {
        // using ghost tracking for successful bribe deposits
        uint16 currentEpoch = governance.epoch();

        for (uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            IBribeInitiative.Bribe memory bribe = ghostBribeByEpoch[initiative][currentEpoch];
            (uint128 boldAmount, uint128 bribeTokenAmount) = IBribeInitiative(initiative).bribeByEpoch(currentEpoch);
            eq(
                bribe.boldAmount,
                boldAmount,
                "BI-06: Accounting for bold amount in bribe for an epoch is always correct"
            );
            eq(
                bribe.bribeTokenAmount,
                bribeTokenAmount,
                "BI-06: Accounting for bold amount in bribe for an epoch is always correct"
            );
        }
    }

    function property_BI07() public {
        uint16 currentEpoch = governance.epoch();

        // sum user allocations for an epoch
        // check that this matches the total allocation for the epoch
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            uint88 sumLqtyAllocated;
            for (uint8 j; j < users.length; j++) {
                address user = users[j];
                (uint88 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
                sumLqtyAllocated += lqtyAllocated;
            }
            (uint88 totalLQTYAllocated,) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
            eq(
                sumLqtyAllocated,
                totalLQTYAllocated,
                "BI-07: Sum of user LQTY allocations for an epoch != total LQTY allocation for the epoch"
            );
        }
    }

    function property_sum_of_votes_in_bribes_match() public {
        uint16 currentEpoch = governance.epoch();

        // sum user allocations for an epoch
        // check that this matches the total allocation for the epoch
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            uint256 sumOfPower;
            for (uint8 j; j < users.length; j++) {
                (uint88 lqtyAllocated, uint32 userTS) = initiative.lqtyAllocatedByUserAtEpoch(users[j], currentEpoch);
                sumOfPower += governance.lqtyToVotes(lqtyAllocated, userTS, uint32(block.timestamp));
            }
            (uint88 totalLQTYAllocated, uint32 totalTS) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);

            uint256 totalRecordedPower = governance.lqtyToVotes(totalLQTYAllocated, totalTS, uint32(block.timestamp));

            gte(totalRecordedPower, sumOfPower, "property_sum_of_votes_in_bribes_match");
        }
    }

    function property_BI08() public {
        // users can only claim for epoch that has already passed
        uint16 checkEpoch = governance.epoch() - 1;

        // use lqtyAllocatedByUserAtEpoch to determine if a user is allocated for an epoch
        // use claimedBribeForInitiativeAtEpoch to determine if user has claimed bribe for an epoch (would require the value changing from false -> true)
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint8 j; j < users.length; j++) {
                (uint88 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);

                // check that user had no lqtyAllocated for the epoch and therefore shouldn't be able to claim for it
                if (lqtyAllocated == 0) {
                    // since bool could only possibly change from false -> true, just check that it's the same before and after
                    bool claimedBefore =
                        _before.claimedBribeForInitiativeAtEpoch[address(initiative)][users[j]][checkEpoch];
                    bool claimedAfter =
                        _before.claimedBribeForInitiativeAtEpoch[address(initiative)][users[j]][checkEpoch];
                    t(
                        claimedBefore == claimedAfter,
                        "BI-08: User cannot claim bribes for an epoch in which they are not allocated"
                    );
                }
            }
        }
    }

    // BI-09: User can’t be allocated for future epoch
    function property_BI09() public {
        // get one past current epoch in governance
        uint16 checkEpoch = governance.epoch() + 1;
        // check if any user is allocated for the epoch
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint8 j; j < users.length; j++) {
                (uint88 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);

                eq(lqtyAllocated, 0, "BI-09: User cannot be allocated for future epoch");
            }
        }
    }

    // BI-10: totalLQTYAllocatedByEpoch ≥ lqtyAllocatedByUserAtEpoch
    function property_BI10() public {
        uint16 checkEpoch = governance.epoch();

        // check each user allocation for the epoch against the total for the epoch
        for (uint8 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint8 j; j < users.length; j++) {
                (uint88 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);
                (uint88 totalLQTYAllocated,) = initiative.totalLQTYAllocatedByEpoch(checkEpoch);

                gte(totalLQTYAllocated, lqtyAllocated, "BI-10: totalLQTYAllocatedByEpoch >= lqtyAllocatedByUserAtEpoch");
            }
        }
    }

    // BI-11: User can always claim a bribe amount for which they are entitled
    function property_BI11() public {
        // unableToClaim gets set in the call to claimBribes and checks if user had a claimable allocation that wasn't yet claimed and tried to claim it unsuccessfully
        t(!unableToClaim, "BI-11: User can always claim a bribe amount for which they are entitled ");
    }
}
