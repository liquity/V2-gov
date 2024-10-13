
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {IBribeInitiative} from "../../src/interfaces/IBribeInitiative.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";


abstract contract TargetFunctions is Test, BaseTargetFunctions, Properties, BeforeAfter {
    function initiative_depositBribe(uint128 boldAmount, uint128 bribeTokenAmount, uint16 epoch) public {
        // clamp token amounts using user balance
        boldAmount = uint128(boldAmount % lusd.balanceOf(user));
        bribeTokenAmount = uint128(bribeTokenAmount % lqty.balanceOf(user));

        initiative.depositBribe(boldAmount, bribeTokenAmount, epoch);
    }

    function initiative_claimBribes(uint16 epoch, uint16 prevAllocationEpoch, uint16 prevTotalAllocationEpoch) public {        
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

        initiative.claimBribes(claimData);
    }

    // NOTE: governance function for setting allocations that's needed to test claims
    function initiative_onAfterAllocateLQTY(bool vote, uint88 voteLQTY, uint88 vetoLQTY) public {
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
    }

    // allows the fuzzer to change the governance epoch for more realistic testing
    function governance_setEpoch(uint16 epoch) public {
        // only allow epoch to increase to not cause issues
        epoch = uint16(bound(epoch, governance.epoch(), type(uint16).max));
        require(epoch > governance.epoch()); // added check for potential issues with downcasting from uint256 to uint16
        
        governance.setEpoch(epoch);
    }
}
