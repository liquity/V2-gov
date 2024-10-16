
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "../TargetFunctions.sol";
import {Governance} from "src/Governance.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {console} from "forge-std/console.sol";


contract TrophiesToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }
		
// forge test --match-test test_property_sum_of_lqty_global_user_matches_0 -vv 
// NOTE: This property breaks and that's the correct behaviour
// Because we remove the counted votes from total state
// Then the user votes will remain allocated
// But they are allocated to a DISABLED strategy
// Due to this, the count breaks
// We can change the property to ignore DISABLED strategies
// Or we would have to rethink the architecture 
function test_property_sum_of_lqty_global_user_matches_0() public {

   vm.roll(161622);
   vm.warp(block.timestamp + 1793404);
   vm.prank(0x0000000000000000000000000000000000030000);
   property_sum_of_lqty_global_user_matches();
  
   vm.roll(273284);
   vm.warp(block.timestamp + 3144198);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(3501478328989062228745782);
  
   vm.roll(273987);
   vm.warp(block.timestamp + 3148293);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 5285836763643083359055120749, 0);


   governance_unregisterInitiative(0);
   property_sum_of_lqty_global_user_matches();
}


}