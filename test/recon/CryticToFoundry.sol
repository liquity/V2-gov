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

    // forge test --match-test test_property_BI03_1 -vv 
    function test_property_BI03_1() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 239415);
        governance_depositLQTY(2);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 366071);
        governance_allocateLQTY_clamped_single_initiative(0,1,0);
        check_skip_consistecy(0);
        property_BI03();
    }

    // forge test --match-test test_property_BI04_4 -vv 
    function test_property_BI04_4() public {
        governance_depositLQTY(2);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 606998);
        governance_allocateLQTY_clamped_single_initiative(0,0,1);
        property_BI04();
    }
}