
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {IBribeInitiative} from "../../src/interfaces/IBribeInitiative.sol";
import {DoubleLinkedList} from "../../src/utils/DoubleLinkedList.sol";
import {Properties} from "./Properties.sol";


abstract contract TargetFunctions is Test, BaseTargetFunctions, Properties {
    using DoubleLinkedList for DoubleLinkedList.List;

    function initiative_depositBribe(uint128 boldAmount, uint128 bribeTokenAmount, uint16 epoch) withChecks public {
        // clamp token amounts using user balance
        boldAmount = uint128(boldAmount % lusd.balanceOf(user));
        bribeTokenAmount = uint128(bribeTokenAmount % lqty.balanceOf(user));

        initiative.depositBribe(boldAmount, bribeTokenAmount, epoch);
    }

    function initiative_claimBribes(uint16 epoch, uint16 prevAllocationEpoch, uint16 prevTotalAllocationEpoch) withChecks public {        
        // clamp epochs by using the current governance epoch
        epoch = epoch % governance.epoch();
        prevAllocationEpoch = prevAllocationEpoch % governance.epoch();
        prevTotalAllocationEpoch = prevTotalAllocationEpoch % governance.epoch();

        IBribeInitiative.ClaimData[] memory claimData = new IBribeInitiative.ClaimData[](1); 
        claimData[0] =  IBribeInitiative.ClaimData({
            epoch: epoch,
            prevLQTYAllocationEpoch: prevAllocationEpoch,
            prevTotalLQTYAllocationEpoch: prevTotalAllocationEpoch
        });

        bool alreadyClaimed = initiative.claimedBribeAtEpoch(user, epoch);

        initiative.claimBribes(claimData);

        // check if the bribe was already claimed at the given epoch
        if(alreadyClaimed) {
            // toggle canary that breaks the BI-02 property
            claimedTwice = true;
        }
    }

    // NOTE: governance function for setting allocations that's needed to test claims
    function initiative_onAfterAllocateLQTY(bool vote, uint88 voteLQTY, uint88 vetoLQTY) withChecks public {
        uint16 currentEpoch = governance.epoch();
        // use this bool to replicate user decision to vote or veto so that fuzzer doesn't do both since this is blocked by governance
        if(vote) {
            voteLQTY = uint88(voteLQTY % lqty.balanceOf(user));
            vetoLQTY = 0;
        } else {
            vetoLQTY = uint88(voteLQTY % lqty.balanceOf(user));
            voteLQTY = 0;
        }
        
        vm.prank(address(governance));
        IInitiative(address(initiative)).onAfterAllocateLQTY(currentEpoch, user, voteLQTY, vetoLQTY);

        // if the call was successful, update the ghost tracking variables for user allocations
        if(vote) {
            // user allocation only increases if the user voted, no allocation increase for vetoing
            // read value from storage
            uint16 mostRecentUserEpoch = ghostLqtyAllocationByUserAtEpoch[user].getHead();

            if(mostRecentUserEpoch != currentEpoch) {
                ghostLqtyAllocationByUserAtEpoch[user].insert(currentEpoch, voteLQTY, 0);
            } else {
                ghostLqtyAllocationByUserAtEpoch[user].items[currentEpoch].value = voteLQTY;
            }
        }

        // only have one user so just need to acccumulate for them
        ghostTotalAllocationAtEpoch[currentEpoch] += initiative.lqtyAllocatedByUserAtEpoch(user, currentEpoch);
    }

    // allows the fuzzer to change the governance epoch for more realistic testing
    function governance_setEpoch(uint16 epoch) public {
        // only allow epoch to increase to not cause issues
        epoch = uint16(bound(epoch, governance.epoch(), type(uint16).max));
        require(epoch > governance.epoch()); // added check for potential issues with downcasting from uint256 to uint16
        
        governance.setEpoch(epoch);
    }
}
