// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {Governance} from "src/Governance.sol";

import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-test test_optimize_property_sum_of_initatives_matches_total_votes_insolvency_0 -vv
    // Example broken property due to rounding errors
    function test_optimize_property_sum_of_initatives_matches_total_votes_insolvency_0() public {
        vm.warp(block.timestamp + 574062);

        vm.roll(block.number + 280);

        governance_depositLQTY_2(106439091954186822399173735);

        vm.roll(block.number + 748);
        vm.warp(block.timestamp + 75040);
        governance_depositLQTY(2116436955066717227177);

        governance_allocateLQTY_clamped_single_initiative(1, 1, 0);

        helper_deployInitiative();

        governance_registerInitiative(1);

        vm.warp(block.timestamp + 566552);

        vm.roll(block.number + 23889);

        governance_allocateLQTY_clamped_single_initiative_2nd_user(31, 1314104679369829143691540410, 0);
        (,, uint256 votedPowerSum, uint256 govPower) = _getInitiativeStateAndGlobalState();
        console.log("votedPowerSum", votedPowerSum);
        console.log("govPower", govPower);

        assertTrue(optimize_property_sum_of_initatives_matches_total_votes_insolvency());
    }
}
