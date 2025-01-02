// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "../TargetFunctions.sol";
import {Governance} from "src/Governance.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {console} from "forge-std/console.sol";

contract TrophiesToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-test test_check_unregisterable_consistecy_0 -vv
    /// This shows another issue tied to snapshot vs voting
    /// This state transition will not be possible if you always unregister an initiative
    /// But can happen if unregistering is skipped
    // function test_check_unregisterable_consistecy_0() public {
    /// TODO AUDIT Known bug
    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 385918);
    //     governance_depositLQTY(2);

    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 300358);
    //     governance_allocateLQTY_clamped_single_initiative(0, 0, 1);

    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 525955);
    //     property_resetting_never_reverts();

    //     uint256 state = _getInitiativeStatus(_getDeployedInitiative(0));
    //     assertEq(state, 5, "Should not be this tbh");
    //     // check_unregisterable_consistecy(0);
    //     uint256 epoch = _getLastEpochClaim(_getDeployedInitiative(0));

    //     console.log(epoch + governance.UNREGISTRATION_AFTER_EPOCHS() < governance.epoch() - 1);

    //     vm.warp(block.timestamp + governance.EPOCH_DURATION());
    //     uint256 newState = _getInitiativeStatus(_getDeployedInitiative(0));

    //     uint256 lastEpochClaim = _getLastEpochClaim(_getDeployedInitiative(0));

    //     console.log("governance.UNREGISTRATION_AFTER_EPOCHS()", governance.UNREGISTRATION_AFTER_EPOCHS());
    //     console.log("governance.epoch()", governance.epoch());

    //     console.log(lastEpochClaim + governance.UNREGISTRATION_AFTER_EPOCHS() < governance.epoch() - 1);

    //     console.log("lastEpochClaim", lastEpochClaim);

    //     assertEq(epoch, lastEpochClaim, "epochs");
    //     assertEq(newState, state, "??");
    // }

    function _getLastEpochClaim(address _initiative) internal returns (uint256) {
        (, uint256 epoch,) = governance.getInitiativeState(_initiative);
        return epoch;
    }
}
