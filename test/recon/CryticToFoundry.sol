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

    // forge test --match-test test_optimize_max_claim_underpay_assertion_0 -vv 
 function test_optimize_max_claim_underpay_assertion_0() public {

     helper_accrueBold(1001125329789697909641);

     check_warmup_unregisterable_consistency(0);

     optimize_max_claim_underpay_assertion();

 }
 
// forge test --match-test test_property_sum_of_initatives_matches_total_votes_insolvency_assertion_mid_0 -vv 
 function test_property_sum_of_initatives_matches_total_votes_insolvency_assertion_mid_0() public {

     governance_depositLQTY_2(1439490298322854874);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 313704);
     governance_depositLQTY(1);

     vm.warp(block.timestamp + 413441);

     vm.roll(block.number + 1);

     governance_allocateLQTY_clamped_single_initiative(0,1,0);

     vm.warp(block.timestamp + 173473);

     vm.roll(block.number + 1);

     helper_deployInitiative();

     governance_registerInitiative(1);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 315415);
     governance_allocateLQTY_clamped_single_initiative_2nd_user(1,1293868687551209131,0);

     property_sum_of_initatives_matches_total_votes_insolvency_assertion_mid();

 }

}
