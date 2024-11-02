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
    // forge test --match-test test_property_BI11_0 -vv 
 function test_property_BI11_0() public {

     vm.warp(block.timestamp + 487191);

     vm.roll(block.number + 1);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 282660);
     governance_depositLQTY(1);

     governance_allocateLQTY_clamped_single_initiative(0,1,0);

     initiative_depositBribe(0,1,3,0);

     vm.warp(block.timestamp + 484046);

     vm.roll(block.number + 5445);

     initiative_claimBribes(443,0,0,0);

     property_BI11(); // invalid-prev-lqty-allocation-epoch

 }

// forge test --match-test test_property_BI05_3 -vv 
 function test_property_BI05_3() public {

 initiative_depositBribe(107078662,31,2,0);

     vm.warp(block.timestamp + 607467);

     vm.roll(block.number + 1);

 property_BI05();

 }
// forge test --match-test test_can_claim -vv 
 function test_can_claim() public {
     vm.warp(block.timestamp + governance.EPOCH_DURATION());
    depositTsIsRational(1);
    initiative_depositBribe(1,0,3,0);
    governance_allocateLQTY_clamped_single_initiative(0, 1, 0);
    vm.warp(block.timestamp + governance.EPOCH_DURATION()); // 4
    assertEq(governance.epoch(), 4, "4th epoch");
    initiative_claimBribes(3, 3, 3, 0);
    canary_has_claimed();
 }

}
