// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";
import {Governance} from "src/Governance.sol";

abstract contract BeforeAfter is Setup, Asserts {
    struct Vars {
        uint256 epoch;
        mapping(address => IGovernance.InitiativeStatus) initiativeStatus;
        // initiative => user => epoch => claimed
        mapping(address => mapping(address => mapping(uint256 => bool))) claimedBribeForInitiativeAtEpoch;
        mapping(address user => uint256 lqtyBalance) userLqtyBalance;
        mapping(address user => uint256 lusdBalance) userLusdBalance;
    }

    Vars internal _before;
    Vars internal _after;

    modifier withChecks() {
        __before();
        _;
        __after();
    }

    function __before() internal {
        uint256 currentEpoch = governance.epoch();
        _before.epoch = currentEpoch;
        for (uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _before.initiativeStatus[initiative] = status;
            _before.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] =
                IBribeInitiative(initiative).claimedBribeAtEpoch(user, currentEpoch);
        }

        for (uint8 j; j < users.length; j++) {
            _before.userLqtyBalance[users[j]] = uint256(lqty.balanceOf(user));
            _before.userLusdBalance[users[j]] = uint256(lusd.balanceOf(user));
        }
    }

    function __after() internal {
        uint256 currentEpoch = governance.epoch();
        _after.epoch = currentEpoch;
        for (uint8 i; i < deployedInitiatives.length; i++) {
            address initiative = deployedInitiatives[i];
            (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
            _after.initiativeStatus[initiative] = status;
            _after.claimedBribeForInitiativeAtEpoch[initiative][user][currentEpoch] =
                IBribeInitiative(initiative).claimedBribeAtEpoch(user, currentEpoch);
        }

        for (uint8 j; j < users.length; j++) {
            _after.userLqtyBalance[users[j]] = uint256(lqty.balanceOf(user));
            _after.userLusdBalance[users[j]] = uint256(lusd.balanceOf(user));
        }
    }
}
