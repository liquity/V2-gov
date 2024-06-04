// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {StakingV2} from "../src/StakingV2.sol";



contract StakingV2Test is Test {
    IERC20 constant private lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    address constant private stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address constant private user = address(0x64690353808dBcC843F95e30E071a0Ae6339EE1b);

    StakingV2 private stakingV2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        stakingV2 = new StakingV2(stakingV1);
    }

    function test_depositLQTY() public {
        vm.startPrank(user);
        lqty.approve(address(stakingV2), 1);
        stakingV2.depositLQTY(1);
        vm.stopPrank();
    }
}
