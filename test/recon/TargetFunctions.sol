// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {console2} from "forge-std/Test.sol";

import {Properties} from "./Properties.sol";
import {GovernanceTargets} from "./targets/GovernanceTargets.sol";
import {BribeInitiativeTargets} from "./targets/BribeInitiativeTargets.sol";
import {MaliciousInitiative} from "../mocks/MaliciousInitiative.sol";
import {BribeInitiative} from "../../src/BribeInitiative.sol";
import {ILQTYStaking} from "../../src/interfaces/ILQTYStaking.sol";
import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {IUserProxy} from "../../src/interfaces/IUserProxy.sol";
import {PermitParams} from "../../src/utils/Types.sol";

abstract contract TargetFunctions is GovernanceTargets, BribeInitiativeTargets {
    // helper to deploy initiatives for registering that results in more bold transferred to the Governance contract
    function helper_deployInitiative() public withChecks {
        address initiative = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        deployedInitiatives.push(initiative);
    }

    // helper to simulate bold accrual in Governance contract
    function helper_accrueBold(uint256 boldAmount) public withChecks {
        boldAmount = uint256(boldAmount % lusd.balanceOf(user));
        // target contract is the user so it can transfer directly
        lusd.transfer(address(governance), boldAmount);
    }
}
