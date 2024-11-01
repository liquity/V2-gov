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
// forge test --match-test test_property_BI07_4 -vv 
 function test_property_BI07_4() public {

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 50976);
     governance_depositLQTY_2(2);

     vm.warp(block.timestamp + 554137);

     vm.roll(block.number + 1);

     governance_allocateLQTY_clamped_single_initiative_2nd_user(0,1,0);

     vm.warp(block.timestamp + 608747);

     vm.roll(block.number + 1);

     property_BI07();

 }
}
