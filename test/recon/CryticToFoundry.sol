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

    // forge test --match-test test_property_BI05_3 -vv 
 function test_property_BI05_3() public {

     initiative_depositBribe(107078662,31,2,0);

     property_BI05();

 }
  // forge test --match-test test_property_sum_of_initatives_matches_total_votes_bounded_0 -vv 
 function test_property_sum_of_initatives_matches_total_votes_bounded_0() public {

     vm.warp(block.timestamp + 576345);

     vm.roll(block.number + 1);

 governance_depositLQTY(2);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 41489);
 governance_allocateLQTY_clamped_single_initiative(0,1,0);

 governance_depositLQTY_2(3);

     vm.warp(block.timestamp + 455649);

     vm.roll(block.number + 1);

 governance_allocateLQTY_clamped_single_initiative_2nd_user(0,0,2);

     vm.roll(block.number + 1);
     vm.warp(block.timestamp + 136514);
 governance_unregisterInitiative(0);
/**
    // TODO: This property is broken, because if a snapshot was taken before the initiative was unregistered
    /// Then the votes would still be part of the total state
 */
 

 (uint256 initiativeVotesSum, uint256 snapshotVotes) = _getInitiativesSnapshotsAndGlobalState();
 console.log("initiativeVotesSum", initiativeVotesSum);
 console.log("snapshotVotes", snapshotVotes);

 }

}
