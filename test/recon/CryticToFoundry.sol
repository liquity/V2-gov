
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test} from "forge-std/Test.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {MaliciousInitiative} from "../mocks/MaliciousInitiative.sol";


contract CryticToFoundry is TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_claimBribe() public {
        governance_setEpoch(2);

        initiative_depositBribe(4e18, 4e18, 4);

        governance_setEpoch(6);

        initiative_claimBribes(4, 2, 2);
    }
}
