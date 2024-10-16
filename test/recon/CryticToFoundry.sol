
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
		

// forge test --match-test test_property_sum_of_user_initiative_allocations_0 -vv 
 
function test_property_sum_of_user_initiative_allocations_0() public {
  
   vm.roll(2);
   vm.warp(86000000 + 2);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(20338);
   vm.warp(86000000 + 359683);
   vm.prank(0x0000000000000000000000000000000000030000);
   helper_deployInitiative();
  
   vm.roll(35511);
   vm.warp(86000000 + 718072);
   vm.prank(0x0000000000000000000000000000000000030000);
   helper_deployInitiative();
  
   vm.roll(94412);
   vm.warp(86000000 + 999244);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(161790);
   vm.warp(86000000 + 2651694);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(646169017059856542762865);
  
   vm.roll(186721);
   vm.warp(86000000 + 2815428);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_registerInitiative(63);
  
   vm.roll(257296);
   vm.warp(86000000 + 3261349);
   vm.prank(0x0000000000000000000000000000000000020000);
   helper_deployInitiative();
  
   vm.roll(333543);
   vm.warp(86000000 + 4091708);
   vm.prank(0x0000000000000000000000000000000000020000);
   helper_deployInitiative();
  
   vm.roll(368758);
   vm.warp(86000000 + 4314243);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_allocateLQTY_clamped_single_initiative(3, 29956350487679649024950075925, 0);
  
   vm.roll(375687);
   vm.warp(86000000 + 4704876);
   vm.prank(0x0000000000000000000000000000000000020000);
   property_sum_of_user_initiative_allocations();
}
		
}