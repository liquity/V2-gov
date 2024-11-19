// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20Tester} from "./MockERC20Tester.sol";
import {MockStakingV1} from "./MockStakingV1.sol";

function deployMockStakingV1() returns (MockStakingV1 stakingV1, MockERC20Tester lqty, MockERC20Tester lusd) {
    lqty = new MockERC20Tester("Liquity", "LQTY");
    lusd = new MockERC20Tester("Liquity USD", "LUSD");
    stakingV1 = new MockStakingV1(lqty, lusd);

    // Let stakingV1 spend anyone's LQTY without approval, like in the real LQTYStaking
    lqty.mock_setWildcardSpender(address(stakingV1), true);
}
