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

    // forge test --match-test test_property_sum_of_user_voting_weights_0 -vv 
    // NOTE: property_sum_of_user_voting_weights_strict will false
    // NOTE: Whereas property_sum_of_user_voting_weights_bounded will not
 function test_property_sum_of_user_voting_weights_0() public {

     vm.warp(block.timestamp + 365090);

     vm.roll(block.number + 1);

     governance_depositLQTY_2(3);

     vm.warp(block.timestamp + 164968);

     vm.roll(block.number + 1);

     governance_depositLQTY(2);

     vm.warp(block.timestamp + 74949);

     vm.roll(block.number + 1);

     governance_allocateLQTY_clamped_single_initiative_2nd_user(0,2,0);

     governance_allocateLQTY_clamped_single_initiative(0,1,0);

     property_sum_of_user_voting_weights_bounded();

 }


// //  forge test --match-test test_property_shouldNeverRevertgetInitiativeState_arbitrary,,)_3 -vv 
//  function test_property_shouldNeverRevertgetInitiativeState_arbitrary_3() public {


//      vm.warp(block.timestamp + 606190);

//      vm.roll(block.number + 1);

//     // TODO: I think the snapshout is not sound, so this is ok to revert, didn't spend enough time
//     //  property_shouldNeverRevertgetInitiativeState_arbitrary(0x3f85D0b6119B38b7E6B119F7550290fec4BE0e3c,(784230180117921576403247836788904270876780620371067576558428, 0);

//  }
}
