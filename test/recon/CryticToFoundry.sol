
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
    
        vm.roll(block.timestamp + 237680);
        vm.warp(block.number + 2536756);
        vm.prank(0x0000000000000000000000000000000000020000);
        governance_depositLQTY(37207352249250036667298804);
        
        vm.roll(block.timestamp + 273168);
        vm.warp(block.number + 3045913);
        vm.prank(0x0000000000000000000000000000000000010000);
        governance_unregisterInitiative(0);
        
        vm.roll(block.timestamp + 301841);
        vm.warp(block.number + 3350068);
        vm.prank(0x0000000000000000000000000000000000030000);
        property_GV01();
    }
}