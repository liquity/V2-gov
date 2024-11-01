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
    
// forge test --match-test test_property_shouldNeverRevertgetInitiativeState_1 -vv 
// TODO: Fixx with full math
 function test_property_shouldNeverRevertgetInitiativeState_1() public {

     helper_accrueBold(18728106356049635796899970);

     governance_claimForInitiativeFuzzTest(10);

     vm.roll(block.number + 37678);
     vm.warp(block.timestamp + 562841);
     property_sum_of_user_initiative_allocations();

     vm.roll(block.number + 27633);
     vm.warp(block.timestamp + 92508);
     property_BI04();

     check_claim_soundness();

     governance_depositLQTY(16);

     vm.roll(block.number + 16246);
     vm.warp(block.timestamp + 128);
     governance_claimForInitiativeDoesntRevert(1);

     vm.warp(block.timestamp + 289814);

     vm.roll(block.number + 12073);

     vm.roll(block.number + 39586);
     vm.warp(block.timestamp + 84);
     governance_depositLQTY_2(27314363929170282673717281);

     property_viewCalculateVotingThreshold();

     vm.roll(block.number + 2362);
     vm.warp(block.timestamp + 126765);
     helper_deployInitiative();

     vm.roll(block.number + 9675);
     vm.warp(block.timestamp + 313709);
     governance_claimForInitiativeDoesntRevert(13);

     vm.roll(block.number + 51072);
     vm.warp(block.timestamp + 322377);
     property_BI04();

     vm.warp(block.timestamp + 907990);

     vm.roll(block.number + 104736);

     governance_depositLQTY(142249495256913202572780803);

     vm.roll(block.number + 33171);
     vm.warp(block.timestamp + 69345);
     property_BI03();

     vm.warp(block.timestamp + 89650);

     vm.roll(block.number + 105024);

     governance_registerInitiative(7);

     vm.roll(block.number + 32547);
     vm.warp(block.timestamp + 411452);
     property_sum_of_votes_in_bribes_match();

     vm.roll(block.number + 222);
     vm.warp(block.timestamp + 18041);
     initiative_claimBribes(7741,24,96,231);

     vm.roll(block.number + 213);
     vm.warp(block.timestamp + 93910);
     property_BI07();

     property_viewCalculateVotingThreshold();

     property_sum_of_lqty_global_user_matches();

     initiative_claimBribes(8279,2983,19203,63);

     governance_allocateLQTY_clamped_single_initiative_2nd_user(177,999999,0);

     check_skip_consistecy(49);

     property_BI08();

     property_shouldGetTotalVotesAndState();

     property_GV01();

     vm.warp(block.timestamp + 266736);

     vm.roll(block.number + 5014);

     vm.roll(block.number + 12823);
     vm.warp(block.timestamp + 582973);
     check_unregisterable_consistecy(0);

     helper_accrueBold(165945283488494063896927504);

     vm.roll(block.number + 2169);
     vm.warp(block.timestamp + 321375);
     check_skip_consistecy(6);

     governance_resetAllocations();

     governance_allocateLQTY_clamped_single_initiative(151,79228162514264337593543950333,0);

     property_shouldNeverRevertgetInitiativeState(74);

     check_skip_consistecy(60);

     vm.roll(block.number + 4440);
     vm.warp(block.timestamp + 277592);
     property_allocations_are_never_dangerously_high();

     vm.warp(block.timestamp + 991261);

     vm.roll(block.number + 56784);

     vm.roll(block.number + 16815);
     vm.warp(block.timestamp + 321508);
     property_shouldNeverRevertgetInitiativeState(9); // TODO: VERY BAD

 }

 // forge test --match-test test_property_sum_of_initatives_matches_total_votes_2 -vv 
 function test_property_sum_of_initatives_matches_total_votes_2() public {

     governance_depositLQTY_2(2);

     vm.warp(block.timestamp + 284887);

     vm.roll(block.number + 1);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 344203);
     governance_allocateLQTY_clamped_single_initiative_2nd_user(0,1,0);

     helper_deployInitiative();

     governance_depositLQTY(3);

     vm.warp(block.timestamp + 151205);

     vm.roll(block.number + 1);

     governance_registerInitiative(1);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 449161);
     governance_allocateLQTY_clamped_single_initiative(1,1587890,0);

     vm.warp(block.timestamp + 448394);

     vm.roll(block.number + 1);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 152076);
     property_sum_of_initatives_matches_total_votes_bounded();
     property_sum_of_initatives_matches_total_votes_strict();

 }
 // forge test --match-test test_governance_allocateLQTY_clamped_single_initiative_0 -vv 
 function test_governance_allocateLQTY_clamped_single_initiative_0() public {

     vm.warp(block.timestamp + 944858);

     vm.roll(block.number + 5374);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 1803);
     property_sum_of_user_voting_weights_bounded();

     vm.roll(block.number + 335);
     vm.warp(block.timestamp + 359031);
     property_BI08();

     vm.warp(block.timestamp + 586916);

     vm.roll(block.number + 16871);

     vm.roll(block.number + 3);
     vm.warp(block.timestamp + 427175);
     property_sum_of_lqty_initiative_user_matches();

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 132521);
     property_BI11();

     vm.warp(block.timestamp + 19680);

     vm.roll(block.number + 3);

     vm.roll(block.number + 8278);
     vm.warp(block.timestamp + 322253);
     property_shouldNeverRevertgetInitiativeSnapshotAndState(0);

     vm.warp(block.timestamp + 230528);

     vm.roll(block.number + 3414);

     governance_unregisterInitiative(0);

     vm.warp(block.timestamp + 383213);

     vm.roll(block.number + 1);

     helper_deployInitiative();

     depositTsIsRational(3);

     governance_registerInitiative(1);

     vm.warp(block.timestamp + 221024);

     vm.roll(block.number + 2535);

     governance_allocateLQTY_clamped_single_initiative(1,1164962138833407039120303983,1500);

     governance_allocateLQTY_clamped_single_initiative(0,21,32455529079152273943377283375);

 }
}
