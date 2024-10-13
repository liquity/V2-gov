
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {MaliciousInitiative} from "../mocks/MaliciousInitiative.sol";

abstract contract Setup is BaseSetup {

    IInitiative initiative;
    MaliciousInitiative maliciousInitiative;

    address actor = address(this);
    address dummyBold = address(0x123);
    address dummyBribe = address(0x456);

    uint256 constant MIN_GAS_TO_HOOK = 350_000;

    function setup() internal virtual override {
        maliciousInitiative = new MaliciousInitiative();
        initiative = IInitiative(address(maliciousInitiative)); 

        // sets an example out of gas revert reason on the Initiative
        maliciousInitiative.setRevertBehaviour(MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.OOG);
    }
}
