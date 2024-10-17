
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

// forge test --match-test test_property_sum_of_user_voting_weights_2 -vv 
 
function test_property_sum_of_user_voting_weights_2() public {
   vm.roll(107029);
   vm.warp(block.timestamp + 1423117);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(147228);
   vm.warp(block.timestamp + 1951517);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_depositLQTY(10247106764385567105106);
  
   vm.roll(150091);
   vm.warp(block.timestamp + 1963577);
   vm.prank(0x0000000000000000000000000000000000030000);
   governance_allocateLQTY_clamped_single_initiative(0, 2191468131071272092967892235, 0);
  
   vm.roll(156843);
   vm.warp(block.timestamp + 2343870);
   vm.prank(0x0000000000000000000000000000000000010000);
   property_sum_of_user_voting_weights();
}
		
				
}