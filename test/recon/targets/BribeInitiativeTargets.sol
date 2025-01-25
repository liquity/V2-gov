// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {IInitiative} from "src/interfaces/IInitiative.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";
import {DoubleLinkedList} from "src/utils/DoubleLinkedList.sol";
import {Properties} from "../Properties.sol";

abstract contract BribeInitiativeTargets is Test, BaseTargetFunctions, Properties {
    using DoubleLinkedList for DoubleLinkedList.List;

    // NOTE: initiatives that get called here are deployed but not necessarily registered

    function initiative_depositBribe(uint256 boldAmount, uint256 bribeTokenAmount, uint256 epoch, uint8 initiativeIndex)
        public
        withChecks
    {
        IBribeInitiative initiative = IBribeInitiative(_getDeployedInitiative(initiativeIndex));

        // clamp token amounts using user balance
        boldAmount = uint256(boldAmount % lusd.balanceOf(user));
        bribeTokenAmount = uint256(bribeTokenAmount % lqty.balanceOf(user));

        lusd.approve(address(initiative), boldAmount);
        lqty.approve(address(initiative), bribeTokenAmount);

        (uint256 boldAmountB4, uint256 bribeTokenAmountB4,) = IBribeInitiative(initiative).bribeByEpoch(epoch);

        initiative.depositBribe(boldAmount, bribeTokenAmount, epoch);

        (uint256 boldAmountAfter, uint256 bribeTokenAmountAfter,) = IBribeInitiative(initiative).bribeByEpoch(epoch);

        eq(boldAmountB4 + boldAmount, boldAmountAfter, "Bold amount tracking is sound");
        eq(bribeTokenAmountB4 + bribeTokenAmount, bribeTokenAmountAfter, "Bribe amount tracking is sound");
    }

    // Canaries are no longer necessary
    // function canary_bribeWasThere(uint8 initiativeIndex) public {
    //     uint256 epoch = governance.epoch();
    //     IBribeInitiative initiative = IBribeInitiative(_getDeployedInitiative(initiativeIndex));

    //     (uint256 boldAmount, uint256 bribeTokenAmount) = initiative.bribeByEpoch(epoch);
    //     t(boldAmount == 0 && bribeTokenAmount == 0, "A bribe was found");
    // }

    // bool hasClaimedBribes;
    // function canary_has_claimed() public {
    //     t(!hasClaimedBribes, "has claimed");
    // }

    function clamped_claimBribes(uint8 initiativeIndex) public {
        IBribeInitiative initiative = IBribeInitiative(_getDeployedInitiative(initiativeIndex));

        uint256 userEpoch = initiative.getMostRecentUserEpoch(user);
        uint256 stateEpoch = initiative.getMostRecentTotalEpoch();
        initiative_claimBribes(governance.epoch() - 1, userEpoch, stateEpoch, initiativeIndex);
    }

    function initiative_claimBribes(
        uint256 epoch,
        uint256 prevAllocationEpoch,
        uint256 prevTotalAllocationEpoch,
        uint8 initiativeIndex
    ) public withChecks {
        IBribeInitiative initiative = IBribeInitiative(_getDeployedInitiative(initiativeIndex));

        // clamp epochs by using the current governance epoch
        epoch = epoch % governance.epoch();
        prevAllocationEpoch = prevAllocationEpoch % governance.epoch();
        prevTotalAllocationEpoch = prevTotalAllocationEpoch % governance.epoch();

        IBribeInitiative.ClaimData[] memory claimData = new IBribeInitiative.ClaimData[](1);
        claimData[0] = IBribeInitiative.ClaimData({
            epoch: epoch,
            prevLQTYAllocationEpoch: prevAllocationEpoch,
            prevTotalLQTYAllocationEpoch: prevTotalAllocationEpoch
        });

        bool alreadyClaimed = initiative.claimedBribeAtEpoch(user, epoch);

        try initiative.claimBribes(claimData) {
            // Claiming at the same epoch is an issue
            if (alreadyClaimed) {
                // toggle canary that breaks the BI-02 property
                claimedTwice = true;
            }
        } catch {
            // NOTE: This is not a full check, but a sufficient check for some cases
            /// Specifically we may have to look at the user last epoch
            /// And see if we need to port over that balance from then
            (uint256 lqtyAllocated,) = initiative.lqtyAllocatedByUserAtEpoch(user, epoch);
            bool claimedBribe = initiative.claimedBribeAtEpoch(user, epoch);
            if (initiative.getMostRecentTotalEpoch() != prevTotalAllocationEpoch) {
                return; // We are in a edge case
            }

            // Check if there are bribes
            (uint256 boldAmount, uint256 bribeTokenAmount,) = initiative.bribeByEpoch(epoch);
            bool bribeWasThere;
            if (boldAmount != 0 || bribeTokenAmount != 0) {
                bribeWasThere = true;
            }

            if (lqtyAllocated > 0 && !claimedBribe && bribeWasThere) {
                // user wasn't able to claim a bribe they were entitled to
                unableToClaim = true;
                /// @audit Consider adding this as a test once claiming is simplified
            }
        }
    }
}
