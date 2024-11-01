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
    // forge test --match-test test_governance_allocateLQTY_clamped_single_initiative_0 -vv 
 function test_governance_allocateLQTY_clamped_single_initiative_0() public {

     depositTsIsRational(2);

     governance_allocateLQTY_clamped_single_initiative(0,1,0);

 }

 // forge test --match-test test_property_shouldNeverRevertgetInitiativeState_0 -vv 
 function test_property_shouldNeverRevertgetInitiativeState_0() public {

     property_BI05();

     property_BI05();

     vm.roll(block.number + 4976);
     vm.warp(block.timestamp + 276463);
     helper_deployInitiative();

     property_shouldNeverRevertgetInitiativeState_arbitrary(0x00000000000000000000000000000001fffffffE);

     property_allocations_are_never_dangerously_high();

     vm.roll(block.number + 41799);
     vm.warp(block.timestamp + 492951);
     property_shouldGetTotalVotesAndState();

     vm.roll(block.number + 5984);
     vm.warp(block.timestamp + 33);
     property_shouldNeverRevertepoch();

     vm.roll(block.number + 27160);
     vm.warp(block.timestamp + 511328);
     governance_snapshotVotesForInitiative(0x00000000000000000000000000000002fFffFffD);

     helper_accrueBold(178153731388271698868196367);

     vm.warp(block.timestamp + 555654);

     vm.roll(block.number + 56598);

     vm.roll(block.number + 896);
     vm.warp(block.timestamp + 322143);
     depositTsIsRational(170179971686533688480210610);

     vm.roll(block.number + 60461);
     vm.warp(block.timestamp + 66543);
     property_sum_of_votes_in_bribes_match();

     check_warmup_unregisterable_consistency(201);

     vm.roll(block.number + 16926);
     vm.warp(block.timestamp + 466);
     governance_resetAllocations();

     vm.roll(block.number + 159);
     vm.warp(block.timestamp + 220265);
     governance_resetAllocations();

     vm.roll(block.number + 5018);
     vm.warp(block.timestamp + 135921);
     property_viewCalculateVotingThreshold();

     vm.roll(block.number + 4945);
     vm.warp(block.timestamp + 290780);
     property_shouldNeverRevertgetTotalVotesAndState();

     vm.roll(block.number + 39);
     vm.warp(block.timestamp + 191304);
     helper_accrueBold(1532892064);

     vm.warp(block.timestamp + 543588);

     vm.roll(block.number + 75614);

     vm.roll(block.number + 4996);
     vm.warp(block.timestamp + 254414);
     governance_depositLQTY_2(102);

     vm.roll(block.number + 4864);
     vm.warp(block.timestamp + 409296);
     property_BI06();

     governance_resetAllocations();

     vm.roll(block.number + 16086);
     vm.warp(block.timestamp + 244384);
     governance_snapshotVotesForInitiative(0x00000000000000000000000000000002fFffFffD);

     vm.roll(block.number + 7323);
     vm.warp(block.timestamp + 209911);
     property_BI01();

     property_sum_of_lqty_global_user_matches();

     vm.roll(block.number + 30784);
     vm.warp(block.timestamp + 178399);
     governance_resetAllocations();

     vm.roll(block.number + 8345);
     vm.warp(block.timestamp + 322355);
     property_sum_of_user_initiative_allocations();

     governance_claimForInitiativeFuzzTest(252);

     helper_deployInitiative();

     vm.roll(block.number + 16572);
     vm.warp(block.timestamp + 109857);
     governance_claimForInitiativeDoesntRevert(109);

     vm.roll(block.number + 40001);
     vm.warp(block.timestamp + 486890);
     property_shouldNeverRevertsecondsWithinEpoch();

     vm.warp(block.timestamp + 262802);

     vm.roll(block.number + 30011);

     vm.roll(block.number + 124);
     vm.warp(block.timestamp + 246181);
     property_initiative_ts_matches_user_when_non_zero();

     vm.roll(block.number + 4501);
     vm.warp(block.timestamp + 322247);
     governance_claimForInitiativeDoesntRevert(11);

     property_sum_of_lqty_initiative_user_matches();

     vm.warp(block.timestamp + 185598);

     vm.roll(block.number + 20768);

     vm.roll(block.number + 35461);
     vm.warp(block.timestamp + 322365);
     property_viewCalculateVotingThreshold();

     vm.roll(block.number + 48869);
     vm.warp(block.timestamp + 153540);
     helper_deployInitiative();

     vm.roll(block.number + 22189);
     vm.warp(block.timestamp + 110019);
     check_skip_consistecy(67);

     vm.roll(block.number + 51482);
     vm.warp(block.timestamp + 67312);
     property_sum_of_user_voting_weights_bounded();

     vm.roll(block.number + 891);
     vm.warp(block.timestamp + 226151);
     property_shouldNeverRevertgetTotalVotesAndState();

     property_sum_of_user_voting_weights_bounded();

     vm.roll(block.number + 26151);
     vm.warp(block.timestamp + 321509);
     property_shouldNeverRevertsecondsWithinEpoch();

     vm.roll(block.number + 11);
     vm.warp(block.timestamp + 273130);
     property_BI03();

     vm.roll(block.number + 56758);
     vm.warp(block.timestamp + 517973);
     governance_claimForInitiative(10);

     vm.warp(block.timestamp + 50);

     vm.roll(block.number + 2445);

     vm.roll(block.number + 5014);
     vm.warp(block.timestamp + 406789);
     governance_claimForInitiativeDoesntRevert(199);

     vm.roll(block.number + 50113);
     vm.warp(block.timestamp + 541202);
     property_sum_of_user_voting_weights_bounded();

     vm.roll(block.number + 23859);
     vm.warp(block.timestamp + 322287);
     governance_registerInitiative(69);

     vm.roll(block.number + 22702);
     vm.warp(block.timestamp + 221144);
     helper_deployInitiative();

     vm.roll(block.number + 7566);
     vm.warp(block.timestamp + 521319);
     property_GV_09();

     governance_depositLQTY(65457397064557007353296555);

     vm.roll(block.number + 9753);
     vm.warp(block.timestamp + 321508);
     governance_withdrawLQTY_shouldRevertWhenClamped(96161347592613298005890126);

     vm.roll(block.number + 30630);
     vm.warp(block.timestamp + 490165);
     governance_allocateLQTY_clamped_single_initiative(6,26053304446932650778388682093,0);

     vm.roll(block.number + 40539);
     vm.warp(block.timestamp + 449570);
     property_sum_of_lqty_global_user_matches();

     vm.roll(block.number + 59983);
     vm.warp(block.timestamp + 562424);
     property_shouldNeverRevertepochStart(22);

     vm.warp(block.timestamp + 337670);

     vm.roll(block.number + 47904);

     vm.roll(block.number + 234);
     vm.warp(block.timestamp + 361208);
     property_user_ts_is_always_greater_than_start();

     vm.warp(block.timestamp + 1224371);

     vm.roll(block.number + 68410);

     vm.roll(block.number + 14624);
     vm.warp(block.timestamp + 32769);
     property_global_ts_is_always_greater_than_start();

     vm.warp(block.timestamp + 604796);

     vm.roll(block.number + 177);

     property_BI08();

     property_shouldNeverRevertSnapshotAndState(161);

     vm.roll(block.number + 24224);
     vm.warp(block.timestamp + 16802);
     property_shouldNeverRevertgetInitiativeState(16);

 }
}
