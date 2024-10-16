
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
		

// forge test --match-test test_property_sum_of_lqty_global_initiatives_matches_0 -vv 
 
function test_property_sum_of_lqty_global_initiatives_matches_0() public {
  
   vm.roll(13649);
   vm.warp(999999999 + 274226);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_depositLQTY(132009924662042920942);
  
   vm.roll(23204);
   vm.warp(999999999 + 765086);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 6936608807263793400734754831, 0);


console.log("length", users.length);
console.log("length", deployedInitiatives.length);
   vm.roll(52745);
   vm.warp(999999999 + 1351102);
   vm.prank(0x0000000000000000000000000000000000020000);
   
    (
            uint88 totalCountedLQTY, 
            // uint32 after_user_countedVoteLQTYAverageTimestamp // TODO: How do we do this?
        ) = governance.globalState();

   (uint88 user_voteLQTY, ) = _getAllUserAllocations(users[2]);
   console.log("totalCountedLQTY", totalCountedLQTY);
   console.log("user_voteLQTY", user_voteLQTY);

   assertEq(user_voteLQTY, totalCountedLQTY, "Sum matches");

   property_sum_of_lqty_global_user_matches();
}
		
		
}