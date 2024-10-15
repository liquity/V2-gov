
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";
import {Governance} from "src/Governance.sol";


abstract contract BeforeAfter is Setup, Asserts {
    struct Vars {
        uint16 epoch;
        mapping(address => Governance.InitiativeStatus) initiativeStatus;
        // initiative => user => epoch => claimed
        mapping(address => mapping(address => mapping(uint16 => bool))) claimedBribeForInitiativeAtEpoch;
        uint128 lqtyBalance;
        uint128 lusdBalance;
    }

    Vars internal _before;
    Vars internal _after;

    modifier withChecks { 
        __before();
        _;
        __after();
    }

    function __before() internal {
        uint16 currentEpoch = governance.epoch(); 
        _before.epoch = currentEpoch;
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _before.initiativeStatus[initiative] = status;
            _before.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] = IBribeInitiative(initiative).claimedBribeAtEpoch(user, currentEpoch);
        }

        _before.lqtyBalance = uint128(lqty.balanceOf(user));
        _before.lusdBalance = uint128(lusd.balanceOf(user));
    }

    function __after() internal {
        uint16 currentEpoch = governance.epoch(); 
        _after.epoch = currentEpoch;
        for(uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _after.initiativeStatus[initiative] = status;
            _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] = IBribeInitiative(initiative).claimedBribeAtEpoch(user, currentEpoch);
        }

        _after.lqtyBalance = uint128(lqty.balanceOf(user));
        _after.lusdBalance = uint128(lusd.balanceOf(user));
    }
}