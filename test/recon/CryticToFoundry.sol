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
}
