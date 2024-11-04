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

    // forge test --match-test test_optimize_property_sum_of_initatives_matches_total_votes_insolvency_0 -vv 
 function test_optimize_property_sum_of_initatives_matches_total_votes_insolvency_0() public {

     vm.roll(block.number + 558);
     vm.warp(block.timestamp + 579337);
     property_viewCalculateVotingThreshold();

     governance_depositLQTY_2(135265381313312372076874678);

     property_BI08();

     clamped_claimBribes(0);

     property_BI08();

     vm.roll(block.number + 748);
     vm.warp(block.timestamp + 75040);
     governance_depositLQTY(20527889417283919054188006);

     property_sum_of_lqty_initiative_user_matches();

     check_claim_soundness();

     vm.roll(block.number + 5004);
     vm.warp(block.timestamp + 4684);
     governance_allocateLQTY_clamped_single_initiative(34,2,0);

     property_shouldNeverRevertgetInitiativeState(9);

     governance_claimForInitiativeFuzzTest(22);

     property_GV_09();

     vm.warp(block.timestamp + 574528);

     vm.roll(block.number + 4003);

     governance_claimFromStakingV1(43);

     vm.roll(block.number + 2524);
     vm.warp(block.timestamp + 275505);
     check_realized_claiming_solvency();

     check_skip_consistecy(103);

     property_sum_of_lqty_global_user_matches();

     property_GV_09();

     vm.roll(block.number + 4901);
     vm.warp(block.timestamp + 326329);
     property_shouldGetTotalVotesAndState();

     property_shouldNeverRevertgetLatestVotingThreshold();

     property_shouldNeverRevertgetInitiativeState_arbitrary(0x0000000000000000000000000000000000000000);

     governance_claimForInitiative(32);

     clamped_claimBribes(3);

     property_sum_of_user_voting_weights_strict();

     governance_depositLQTY_2(1979816885405880);

     property_shouldNeverRevertsecondsWithinEpoch();

     governance_claimForInitiative(30);

     property_shouldNeverRevertsecondsWithinEpoch();

     helper_deployInitiative();

     vm.warp(block.timestamp + 288562);

     vm.roll(block.number + 125);

     vm.roll(block.number + 6666);
     vm.warp(block.timestamp + 472846);
     clamped_claimBribes(8);

     property_sum_of_user_voting_weights_strict();

     property_sum_of_user_initiative_allocations();

     governance_registerInitiative(53);

     vm.warp(block.timestamp + 566552);

     vm.roll(block.number + 23889);

     helper_deployInitiative();

     property_initiative_ts_matches_user_when_non_zero();

     vm.roll(block.number + 163);
     vm.warp(block.timestamp + 33458);
     property_global_ts_is_always_greater_than_start();

     property_BI02();

     governance_allocateLQTY_clamped_single_initiative_2nd_user(196,20348901936480488809445467738,0);
    (, , uint256 votedPowerSum, uint256 govPower) = _getInitiativeStateAndGlobalState();
    console.log("votedPowerSum", votedPowerSum);
    console.log("govPower", govPower);
    assert(optimize_property_sum_of_initatives_matches_total_votes_insolvency());
 }

}
