
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
   vm.roll(block.number + 54184);
   vm.warp(block.timestamp + 65199);
   vm.prank(0x0000000000000000000000000000000000010000);
   governance_depositLQTY(10618051687797035123500145);
  
   vm.roll(block.number + 103930);
   vm.warp(block.timestamp + 635494);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 0, 1231231);

    (uint88 user_allocatedLQTY, ) = governance.userStates(user);

    assertTrue(user_allocatedLQTY > 0, "Something is allocated");

   // Allocates `10597250933489619569146227`
    (
        uint88 countedVoteLQTY, uint32 countedVoteLQTYAverageTimestamp 
            // uint32 after_user_countedVoteLQTYAverageTimestamp // TODO: How do we do this?
    ) = governance.globalState();
    console.log("countedVoteLQTYAverageTimestamp", countedVoteLQTYAverageTimestamp);
    assertTrue(countedVoteLQTY > 0, "Something is counted");

  
   vm.roll(block.number + 130098);
   vm.warp(block.timestamp + 1006552);
   vm.prank(0x0000000000000000000000000000000000020000);
   property_sum_of_lqty_global_user_matches();
}
		
		
		
}