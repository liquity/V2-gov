
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
  
   vm.roll(39122);
   vm.warp(999999999 +285913);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(42075334510194471637767337);
  
   vm.roll(39152);
   vm.warp(999999999 +613771);
   vm.prank(0x0000000000000000000000000000000000030000);
   helper_deployInitiative();
  
   vm.roll(69177);
   vm.warp(999999999 +936185);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 0, 1696172787721902493372875218);
  
   vm.roll(76883);
   vm.warp(999999999 +1310996);
   vm.prank(0x0000000000000000000000000000000000030000);
   helper_deployInitiative();
  
   vm.roll(94823);
   vm.warp(999999999 +1329974);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(94907);
   vm.warp(999999999 +1330374);
   vm.prank(0x0000000000000000000000000000000000030000);

}
		
		
		
}