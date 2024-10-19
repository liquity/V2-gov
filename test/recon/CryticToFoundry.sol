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

    // forge test --match-test test_property_sum_of_initatives_matches_total_votes_1 -vv
    function test_property_sum_of_initatives_matches_total_votes_1() public {
        vm.warp(block.timestamp + 133118);
        governance_depositLQTY(5);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 500671);
        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);

        governance_depositLQTY(1);

        vm.warp(block.timestamp + 360624);
        helper_deployInitiative();

        governance_registerInitiative(1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 438459);
        governance_allocateLQTY_clamped_single_initiative(1, 5116, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 226259);
        vm.roll(block.number + 1);

        vm.warp(block.timestamp + 157379);
        property_sum_of_initatives_matches_total_votes();
    }

    // forge test --match-test test_property_sum_of_initatives_matches_total_votes_5 -vv
    function test_property_sum_of_initatives_matches_total_votes_5() public {
        governance_depositLQTY(2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 856945);

        governance_allocateLQTY_clamped_single_initiative(0, 133753, 0);
        helper_deployInitiative();

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 315310);
        governance_registerInitiative(1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 366454);
        governance_depositLQTY(1);
        governance_allocateLQTY_clamped_single_initiative(1, 1338466836127459, 0);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 276119);
        property_sum_of_initatives_matches_total_votes();
    }

    // forge test --match-test test_check_unregisterable_consistecy_0 -vv
    function test_check_unregisterable_consistecy_0() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 385918);
        governance_depositLQTY(2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 300358);
        governance_allocateLQTY_clamped_single_initiative(0, 0, 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 525955);
        property_resetting_never_reverts();

        check_unregisterable_consistecy(0);
    }
}
