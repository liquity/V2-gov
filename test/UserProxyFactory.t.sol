// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {UserProxyFactory} from "./../src/UserProxyFactory.sol";

contract UserProxyFactoryTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    UserProxyFactory private userProxyFactory;

    function setUp() public {
        userProxyFactory = new UserProxyFactory(address(lqty), address(lusd), stakingV1);
    }

    function test_deployUserProxy() public {
        address userProxy = userProxyFactory.deriveUserProxyAddress(user);

        vm.startPrank(user);
        assertEq(userProxyFactory.deployUserProxy(), userProxy);
        vm.expectRevert();
        userProxyFactory.deployUserProxy();
        vm.stopPrank();

        userProxyFactory.deployUserProxy();
        assertEq(userProxyFactory.deriveUserProxyAddress(user), userProxy);
    }
}
