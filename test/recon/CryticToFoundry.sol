
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {console} from "forge-std/console.sol";


contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-test test_property_stake_and_votes_cannot_be_abused_0 -vv 
 
function test_property_stake_and_votes_cannot_be_abused_0() public {
  
   vm.roll(97530);
   vm.warp(9999999 + 1271694);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(1442702334050498841417730);
  
   vm.roll(97530);
   vm.warp(9999999 + 1271694);
   vm.prank(0x0000000000000000000000000000000000010000);
   governance_allocateLQTY_clamped_single_initiative(0, 8761103629428999582130786, 0);
  
   vm.roll(137102);
   vm.warp(9999999 + 1602109);
   vm.prank(0x0000000000000000000000000000000000030000);
   property_stake_and_votes_cannot_be_abused();
}
				
}