// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";

import {console} from "forge-std/console.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    /// Example fixed bribes properties
    // Use `https://getrecon.xyz/tools/echidna` to scrape properties into this format
    // forge test --match-test test_property_BI03_1 -vv
    function test_property_BI03_1() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 239415);
        governance_depositLQTY(2);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 366071);
        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);
        check_skip_consistecy(0);
        property_BI03();
    }

    // forge test --match-test test_property_BI04_4 -vv
    function test_property_BI04_4() public {
        governance_depositLQTY(2);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 606998);
        governance_allocateLQTY_clamped_single_initiative(0, 0, 1);
        property_BI04();
    }

    // forge test --match-test test_property_resetting_never_reverts_0 -vv
    function test_property_resetting_never_reverts_0() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 193521);
        governance_depositLQTY(155989603725201422915398867);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 411452);
        governance_allocateLQTY_clamped_single_initiative(0, 0, 154742504910672534362390527);

        property_resetting_never_reverts();
    }

    // forge test --match-test test_property_BI11_3 -vv
    function test_property_BI11_3() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 461046);
        governance_depositLQTY(2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 301396);
        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 450733);
        initiative_claimBribes(0, 3, 0, 0);
        property_BI11();
    }

    // forge test --match-test test_property_BI04_1 -vv
    function test_property_BI04_1() public {
        governance_depositLQTY(2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 654326);
        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 559510);
        property_resetting_never_reverts();

        property_BI04();
    }

    // forge test --match-test test_depositMustFailOnNonZeroAlloc_0 -vv 
 function test_depositMustFailOnNonZeroAlloc_0() public {

     vm.warp(block.timestamp + 471289);

     vm.roll(block.number + 3907);

     vm.roll(block.number + 10486);
     vm.warp(block.timestamp + 202878);
     helper_accrueBold(0);

     vm.roll(block.number + 1363);
     vm.warp(block.timestamp + 88);
     governance_depositLQTY(65537);

     vm.roll(block.number + 55506);
     vm.warp(block.timestamp + 490338);
     property_BI01();

     vm.roll(block.number + 41528);
     vm.warp(block.timestamp + 474682);
     check_unregisterable_consistecy(199);

     vm.roll(block.number + 30304);
     vm.warp(block.timestamp + 267437);
     governance_claimForInitiativeDoesntRevert(135);

     vm.roll(block.number + 49);
     vm.warp(block.timestamp + 322310);
     property_GV01();

     vm.roll(block.number + 17640);
     vm.warp(block.timestamp + 450378);
     property_viewCalculateVotingThreshold();

     vm.warp(block.timestamp + 87032);

     vm.roll(block.number + 16089);

     vm.roll(block.number + 19879);
     vm.warp(block.timestamp + 463587);
     property_BI05();

     vm.roll(block.number + 5054);
     vm.warp(block.timestamp + 322371);
     property_BI08();

     vm.roll(block.number + 5984);
     vm.warp(block.timestamp + 337670);
     property_BI10();

     vm.roll(block.number + 17);
     vm.warp(block.timestamp + 240739);
     check_claim_soundness();

     vm.roll(block.number + 54692);
     vm.warp(block.timestamp + 482340);
     depositMustFailOnNonZeroAlloc(1000000000000000);

 }
}
