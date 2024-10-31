// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "./BeforeAfter.sol";
import {OptimizationProperties} from "./properties/OptimizationProperties.sol";
import {BribeInitiativeProperties} from "./properties/BribeInitiativeProperties.sol";
import {SynchProperties} from "./properties/SynchProperties.sol";

abstract contract Properties is OptimizationProperties, BribeInitiativeProperties, SynchProperties {}
