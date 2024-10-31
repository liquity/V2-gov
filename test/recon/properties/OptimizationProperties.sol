// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {MockStakingV1} from "test/mocks/MockStakingV1.sol";
import {vm} from "@chimera/Hevm.sol";
import {IUserProxy} from "src/interfaces/IUserProxy.sol";

abstract contract OptimizationProperties is BeforeAfter {

    // TODO: Add Optimization for property_sum_of_user_voting_weights
    // TODO: Add Optimization for property_sum_of_lqty_global_user_matches
    // TODO: Add Optimization for property_sum_of_initatives_matches_total_votes

    
    // Optimize for Above and Below

    // These will be the checks that allow to determine how safe the changes are

    // We also need a ratio imo, how multiplicatively high can the ratio get
}
    