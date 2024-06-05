// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "./../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {StakingV2, WAD} from "../src/StakingV2.sol";

contract StakingV2Test is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0x64690353808dBcC843F95e30E071a0Ae6339EE1b);

    StakingV2 private stakingV2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1);
    }

    function test_deployUserProxy() public {
        address userProxy = stakingV2.deriveUserProxyAddress(user);

        vm.startPrank(user);
        assertEq(stakingV2.deployUserProxy(), userProxy);
        vm.expectRevert();
        stakingV2.deployUserProxy();
        vm.stopPrank();

        stakingV2.deployUserProxy();
        assertEq(stakingV2.deriveUserProxyAddress(user), userProxy);
    }

    function test_depositLQTY_withdrawShares() public {
        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        // deposit 1 LQTY
        lqty.approve(address(userProxy), 1e18);
        assertEq(stakingV2.depositLQTY(1e18), 1e18);
        assertEq(stakingV2.sharesByUser(user), 1e18);

        // deposit 2 LQTY
        vm.warp(block.timestamp + 86400 * 30);
        lqty.approve(address(userProxy), 2e18);
        assertEq(stakingV2.depositLQTY(2e18), 2e18 * WAD / stakingV2.currentShareRate());
        assertEq(stakingV2.sharesByUser(user), 1e18 + 2e18 * WAD / stakingV2.currentShareRate());

        // withdraw 0.5 half of shares
        vm.warp(block.timestamp + 86400 * 30);
        assertEq(stakingV2.withdrawShares(stakingV2.sharesByUser(user) / 2), 1.5e18);

        // withdraw remaining shares
        assertEq(stakingV2.withdrawShares(stakingV2.sharesByUser(user)), 1.5e18);

        vm.stopPrank();
    }
}
