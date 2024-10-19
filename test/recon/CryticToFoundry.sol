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

    // forge test --match-test test_property_BI04_0 -vv 
    function test_property_BI04_0() public {

            governance_depositLQTY(2);

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 794178);
            check_skip_consistecy(0);

            IBribeInitiative initiative = IBribeInitiative(_getDeployedInitiative(0));

            (uint88 totalLQTYAllocatedAtEpochPrev, ) = initiative.totalLQTYAllocatedByEpoch(governance.epoch());
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1022610);
            
            governance_allocateLQTY_clamped_single_initiative(0,1,0);

            (uint88 totalLQTYAllocatedAtEpoch, ) = initiative.totalLQTYAllocatedByEpoch(governance.epoch());
            (
                uint88 voteLQTY,
                ,
                ,
                ,
                
            ) = governance.initiativeStates(_getDeployedInitiative(0));

            check_unregisterable_consistecy(0);

            console.log("totalLQTYAllocatedAtEpochPrev", totalLQTYAllocatedAtEpochPrev);
            console.log("totalLQTYAllocatedAtEpoch", totalLQTYAllocatedAtEpoch);
            console.log("voteLQTY", voteLQTY);

            property_BI04();
    }


// forge test --match-test test_property_resetting_never_reverts_0 -vv 
 function test_property_resetting_never_reverts_0() public {

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 193521);
         governance_depositLQTY(155989603725201422915398867);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 411452);
         governance_allocateLQTY_clamped_single_initiative(0,0,154742504910672534362390527);

         property_resetting_never_reverts();

 }

    // forge test --match-test test_property_BI11_3 -vv 
    function test_property_BI11_3() public {

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 461046);
        governance_depositLQTY(2);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 301396);
        governance_allocateLQTY_clamped_single_initiative(0,1,0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 450733);
        initiative_claimBribes(0,3,0,0);
        property_BI11();
    }
}