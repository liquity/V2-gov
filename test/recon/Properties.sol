// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "./BeforeAfter.sol";
import {GovernanceProperties} from "./properties/GovernanceProperties.sol";
import {BribeInitiativeProperties} from "./properties/BribeInitiativeProperties.sol";
import {SynchProperties} from "./properties/SynchProperties.sol";
import {RevertProperties} from "./properties/RevertProperties.sol";

abstract contract Properties is GovernanceProperties, BribeInitiativeProperties, SynchProperties, RevertProperties {}
