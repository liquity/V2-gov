
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_depositLQTY_crytic() public {
        governance_depositLQTY(1e18);
    }

    function test_allocateLQTY_crytic() public {
        governance_depositLQTY(1e18);

        vm.warp(block.timestamp + 7 days);
        governance_allocateLQTY_clamped_single_initiative(0, 5e17, 0);
    }

    function test_registerInitiative_crytic() public {
        governance_registerInitiative(1);
    }
}
