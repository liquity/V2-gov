
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test} from "forge-std/Test.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {MaliciousInitiative} from "../mocks/MaliciousInitiative.sol";


contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_initiative_onRegisterInitiative() public {
        initiative_onRegisterInitiative(5);
    }

    function test_intiative_onUnregisterInitiative() public {
        initiative_onRegisterInitiative(5);
        intiative_onUnregisterInitiative(8);
    }

    function test_initiative_onAfterAllocateLQTY() public {
        maliciousInitiative.setRevertBehaviour(MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.OOG);
        initiative_onAfterAllocateLQTY(5, address(0x101112), uint88(10), uint88(15));
    }

    function test_initiative_onClaimForInitiative() public {
        initiative_onClaimForInitiative(5, 50);
    }
}
