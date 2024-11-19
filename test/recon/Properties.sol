// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// NOTE: OptimizationProperties imports Governance properties, to reuse a few fetchers
import {OptimizationProperties} from "./properties/OptimizationProperties.sol";
import {BribeInitiativeProperties} from "./properties/BribeInitiativeProperties.sol";
import {SynchProperties} from "./properties/SynchProperties.sol";
import {RevertProperties} from "./properties/RevertProperties.sol";
import {TsProperties} from "./properties/TsProperties.sol";

abstract contract Properties is
    OptimizationProperties,
    BribeInitiativeProperties,
    SynchProperties,
    RevertProperties,
    TsProperties
{}
