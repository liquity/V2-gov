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

// forge test --match-test test_property_sum_of_initatives_matches_total_votes_strict_0 -vv 
 function test_property_sum_of_initatives_matches_total_votes_strict_0() public {

     vm.warp(block.timestamp + 162964);

     vm.roll(block.number + 1);

     governance_depositLQTY(2);

     vm.warp(block.timestamp + 471948);

     vm.roll(block.number + 1);

     governance_allocateLQTY_clamped_single_initiative(0,2,0);

     vm.warp(block.timestamp + 344203);

     vm.roll(block.number + 1);

     governance_depositLQTY_2(2);

     helper_deployInitiative();

     governance_registerInitiative(1);

     vm.warp(block.timestamp + 232088);

     vm.roll(block.number + 1);

     governance_allocateLQTY_clamped_single_initiative_2nd_user(1,268004076687567,0);

     property_sum_of_initatives_matches_total_votes_strict();

 }
}
