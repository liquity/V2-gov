// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {IBribeInitiative} from "../../../src/interfaces/IBribeInitiative.sol";

abstract contract BribeInitiativeProperties is BeforeAfter {
    function property_BI01() public {
        uint256 currentEpoch = governance.epoch();

        for (uint256 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            for (uint256 j; j < users.length; j++) {
                // if the bool switches, the user has claimed their bribe for the epoch
                if (
                    _before.claimedBribeForInitiativeAtEpoch[initiative][users[j]][currentEpoch]
                        != _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch]
                ) {
                    // calculate user balance delta of the bribe tokens
                    uint256 userLqtyBalanceDelta = _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
                    uint256 userLusdBalanceDelta = _after.userLusdBalance[users[j]] - _before.userLusdBalance[users[j]];

                    // calculate balance delta as a percentage of the total bribe for this epoch
                    // this is what user DOES receive
                    (uint256 bribeBoldAmount, uint256 bribeBribeTokenAmount,) =
                        IBribeInitiative(initiative).bribeByEpoch(currentEpoch);
                    uint256 lqtyPercentageOfBribe = (userLqtyBalanceDelta * 10_000) / bribeBribeTokenAmount;
                    uint256 lusdPercentageOfBribe = (userLusdBalanceDelta * 10_000) / bribeBoldAmount;

                    // Shift right by 40 bits (128 - 88) to get the 88 most significant bits for needed downcasting to compare with lqty allocations
                    uint256 lqtyPercentageOfBribe88 = uint256(lqtyPercentageOfBribe >> 40);
                    uint256 lusdPercentageOfBribe88 = uint256(lusdPercentageOfBribe >> 40);

                    // calculate user allocation percentage of total for this epoch
                    // this is what user SHOULD receive
                    (uint256 lqtyAllocatedByUserAtEpoch,) =
                        IBribeInitiative(initiative).lqtyAllocatedByUserAtEpoch(users[j], currentEpoch);
                    (uint256 totalLQTYAllocatedAtEpoch,) =
                        IBribeInitiative(initiative).totalLQTYAllocatedByEpoch(currentEpoch);
                    uint256 allocationPercentageOfTotal =
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
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);

            (uint256 voteLQTY,,,, uint256 epoch) =
                governance.lqtyAllocatedByUserToInitiative(user, deployedInitiatives[i]);

            try initiative.lqtyAllocatedByUserAtEpoch(user, epoch) returns (uint256 amt, uint256) {
                eq(voteLQTY, amt, "Allocation must match");
            } catch {
                t(false, "Allocation doesn't match governance");
            }
        }
    }

    function property_BI04() public {
        uint256 currentEpoch = governance.epoch();
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);

            // NOTE: This doesn't revert in the future!
            uint256 lastKnownLQTYAlloc = _getLastLQTYAllocationKnown(initiative, currentEpoch);

            // We compare when we don't get a revert (a change happened this epoch)

            (uint256 voteLQTY,,,,) = governance.initiativeStates(deployedInitiatives[i]);

            eq(lastKnownLQTYAlloc, voteLQTY, "BI-04: Initiative Account matches governace");
        }
    }

    function _getLastLQTYAllocationKnown(IBribeInitiative initiative, uint256 targetEpoch)
        internal
        view
        returns (uint256)
    {
        uint256 mostRecentTotalEpoch = initiative.getMostRecentTotalEpoch();
        (uint256 totalLQTYAllocatedAtEpoch,) = initiative.totalLQTYAllocatedByEpoch(
            (targetEpoch < mostRecentTotalEpoch) ? targetEpoch : mostRecentTotalEpoch
        );
        return totalLQTYAllocatedAtEpoch;
    }

    // TODO: Looks pretty wrong and inaccurate
    // Loop over the initiative
    // Have all users claim all
    // See what the result is
    // See the dust
    // Dust cap check
    // function property_BI05() public {
    //     // users can't claim for current epoch so checking for previous
    //     uint256 checkEpoch = governance.epoch() - 1;

    //     for (uint256 i; i < deployedInitiatives.length; i++) {
    //         address initiative = deployedInitiatives[i];
    //         // for any epoch: expected balance = Bribe - claimed bribes, actual balance = bribe token balance of initiative
    //         // so if the delta between the expected and actual is > 0, dust is being collected

    //         uint256 lqtyClaimedAccumulator;
    //         uint256 lusdClaimedAccumulator;
    //         for (uint256 j; j < users.length; j++) {
    //             // if the bool switches, the user has claimed their bribe for the epoch
    //             if (
    //                 _before.claimedBribeForInitiativeAtEpoch[initiative][user][checkEpoch]
    //                     != _after.claimedBribeForInitiativeAtEpoch[initiative][user][checkEpoch]
    //             ) {
    //                 // add user claimed balance delta to the accumulator
    //                 lqtyClaimedAccumulator += _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
    //                 lusdClaimedAccumulator += _after.userLqtyBalance[users[j]] - _before.userLqtyBalance[users[j]];
    //             }
    //         }

    //         (uint256 boldAmount, uint256 bribeTokenAmount) = IBribeInitiative(initiative).bribeByEpoch(checkEpoch);

    //         // shift 128 bit to the right to get the most significant bits of the accumulator (256 - 128 = 128)
    //         uint256 lqtyClaimedAccumulator128 = uint256(lqtyClaimedAccumulator >> 128);
    //         uint256 lusdClaimedAccumulator128 = uint256(lusdClaimedAccumulator >> 128);

    //         // find delta between bribe and claimed amount (how much should be remaining in contract)
    //         uint256 lusdDelta = boldAmount - lusdClaimedAccumulator128;
    //         uint256 lqtyDelta = bribeTokenAmount - lqtyClaimedAccumulator128;

    //         uint256 initiativeLusdBalance = uint256(lusd.balanceOf(initiative) >> 128);
    //         uint256 initiativeLqtyBalance = uint256(lqty.balanceOf(initiative) >> 128);

    //         lte(
    //             lusdDelta - initiativeLusdBalance,
    //             1e8,
    //             "BI-05: Bold token dust amount remaining after claiming should be less than 100 million wei"
    //         );
    //         lte(
    //             lqtyDelta - initiativeLqtyBalance,
    //             1e8,
    //             "BI-05: Bribe token dust amount remaining after claiming should be less than 100 million wei"
    //         );
    //     }
    // }

    function property_BI07() public {
        // sum user allocations for an epoch
        // check that this matches the total allocation for the epoch
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            uint256 currentEpoch = initiative.getMostRecentTotalEpoch();

            uint256 sumLqtyAllocated;
            for (uint256 j; j < users.length; j++) {
                // NOTE: We need to grab user latest
                uint256 userEpoch = initiative.getMostRecentUserEpoch(users[j]);
                (uint256 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], userEpoch);
                sumLqtyAllocated += lqtyAllocated;
            }

            (uint256 totalLQTYAllocated,) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);
            eq(
                sumLqtyAllocated,
                totalLQTYAllocated,
                "BI-07: Sum of user LQTY allocations for an epoch != total LQTY allocation for the epoch"
            );
        }
    }

    function property_sum_of_votes_in_bribes_match() public {
        uint256 currentEpoch = governance.epoch();

        // sum user allocations for an epoch
        // check that this matches the total allocation for the epoch
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            uint256 sumOfPower;
            for (uint256 j; j < users.length; j++) {
                (uint256 lqtyAllocated, uint256 userTS) = initiative.lqtyAllocatedByUserAtEpoch(users[j], currentEpoch);
                sumOfPower += governance.lqtyToVotes(lqtyAllocated, userTS, uint256(block.timestamp));
            }
            (uint256 totalLQTYAllocated, uint256 totalTS) = initiative.totalLQTYAllocatedByEpoch(currentEpoch);

            uint256 totalRecordedPower = governance.lqtyToVotes(totalLQTYAllocated, totalTS, uint256(block.timestamp));

            gte(totalRecordedPower, sumOfPower, "property_sum_of_votes_in_bribes_match");
        }
    }

    function property_BI08() public {
        // users can only claim for epoch that has already passed
        uint256 checkEpoch = governance.epoch() - 1;

        // use lqtyAllocatedByUserAtEpoch to determine if a user is allocated for an epoch
        // use claimedBribeForInitiativeAtEpoch to determine if user has claimed bribe for an epoch (would require the value changing from false -> true)
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint256 j; j < users.length; j++) {
                (uint256 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);

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
        uint256 checkEpoch = governance.epoch() + 1;
        // check if any user is allocated for the epoch
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint256 j; j < users.length; j++) {
                (uint256 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);

                eq(lqtyAllocated, 0, "BI-09: User cannot be allocated for future epoch");
            }
        }
    }

    // BI-10: totalLQTYAllocatedByEpoch ≥ lqtyAllocatedByUserAtEpoch
    function property_BI10() public {
        uint256 checkEpoch = governance.epoch();

        // check each user allocation for the epoch against the total for the epoch
        for (uint256 i; i < deployedInitiatives.length; i++) {
            IBribeInitiative initiative = IBribeInitiative(deployedInitiatives[i]);
            for (uint256 j; j < users.length; j++) {
                (uint256 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(users[j], checkEpoch);
                (uint256 totalLQTYAllocated,) = initiative.totalLQTYAllocatedByEpoch(checkEpoch);

                gte(totalLQTYAllocated, lqtyAllocated, "BI-10: totalLQTYAllocatedByEpoch >= lqtyAllocatedByUserAtEpoch");
            }
        }
    }
}
