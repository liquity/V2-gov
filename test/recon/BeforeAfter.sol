
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Governance} from "../../src/Governance.sol";


abstract contract BeforeAfter is Setup, Asserts {
    struct Vars {
        uint16 epoch;
        mapping(address => Governance.InitiativeStatus) initiativeStatus;
    }

    Vars internal _before;
    Vars internal _after;

    modifier withChecks { 
        __before();
        _;
        __after();
    }

    function __before() internal {
        _before.epoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _before.initiativeStatus[initiative] = status;
        }
    }

    function __after() internal {
        _before.epoch = governance.epoch();
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _after.initiativeStatus[initiative] = status;
        }
    }
}