
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
		
// forge test --match-test test_property_sum_of_lqty_global_user_matches_0 -vv 
 
function test_property_sum_of_lqty_global_user_matches_0() public {
  
   vm.roll(161622);
   vm.warp(9999999999 + 1793404);
   vm.prank(0x0000000000000000000000000000000000030000);
   property_sum_of_lqty_global_user_matches();
  
   vm.roll(273284);
   vm.warp(9999999999 + 3144198);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(3501478328989062228745782);
  
   vm.roll(273987);
   vm.warp(9999999999 + 3148293);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 5285836763643083359055120749, 0);
  
   vm.roll(303163);
   vm.warp(9999999999 + 3234641);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_unregisterInitiative(0);
  
   vm.roll(303170);
   vm.warp(9999999999 + 3234929);
   vm.prank(0x0000000000000000000000000000000000010000);
   property_sum_of_lqty_global_user_matches();
}
		
		
		
		
}