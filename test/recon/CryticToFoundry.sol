
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

// forge test --match-test test_property_GV01_0 -vv 
 
function test_property_GV01_0() public {
  
   vm.roll(block.number + 4921);
   vm.warp(block.timestamp + 277805);
   vm.prank(0x0000000000000000000000000000000000020000);
   helper_deployInitiative();
  
   vm.roll(block.number + 17731);
   vm.warp(block.timestamp + 661456);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(block.number + 41536);
   vm.warp(block.timestamp + 1020941);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(block.number + 41536);
   vm.warp(block.timestamp + 1020941);
   vm.prank(0x0000000000000000000000000000000000010000);
   helper_deployInitiative();
  
   vm.roll(block.number + 41536);
   vm.warp(block.timestamp + 1020941);
   vm.prank(0x0000000000000000000000000000000000020000);
   helper_deployInitiative();
  
   vm.roll(block.number + 61507);
   vm.warp(block.timestamp + 1049774);
   vm.prank(0x0000000000000000000000000000000000020000);
   governance_registerInitiative(22);
  
   vm.roll(block.number + 61507);
   vm.warp(block.timestamp + 1049774);
   vm.prank(0x0000000000000000000000000000000000030000);
   property_GV01();
}
		
		
}