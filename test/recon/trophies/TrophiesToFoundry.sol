
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
   vm.warp(9999999 + 1793404);
   vm.prank(0x0000000000000000000000000000000000030000);
   property_sum_of_lqty_global_user_matches();
  
   vm.roll(273284);
   vm.warp(9999999 + 3144198);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(3501478328989062228745782);
  
   vm.roll(273987);
   vm.warp(9999999 + 3148293);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 5285836763643083359055120749, 0);


   governance_unregisterInitiative(0);
   property_sum_of_lqty_global_user_matches();
}

// forge test --match-test test_property_sum_of_user_voting_weights_0 -vv 
 
 // This is arguably not the full picture in terms of the bug we flagged

function test_property_sum_of_user_voting_weights_0() public {
  
   vm.roll(157584);
   vm.warp(9999999 + 2078708);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_depositLQTY(179977925561450347687);
    
   
   vm.roll(160447);
//    vm.warp(9999999 + 2090768);
   vm.prank(0x0000000000000000000000000000000000030000);
    console.log("time left", governance.secondsWithinEpoch());
   governance_allocateLQTY_clamped_single_initiative(8, 3312598042733079113433328162, 0);
  
   vm.roll(170551);
   vm.warp(9999999 + 2552053);
   vm.prank(0x0000000000000000000000000000000000010000);
   governance_depositLQTY(236641634062530584032535593);
  
   vm.roll(191666);
   vm.warp(9999999 + 2763710);
   vm.prank(0x0000000000000000000000000000000000020000);
   property_sum_of_user_voting_weights();


   // Technically this is intended because the user will have allocated less than 100%
   // However, in sum this causes a bug that makes the early votes valid more than intended
   // Or more specifically the newer votes are not sufficiently discounted when considering how good the early votes are
}


}