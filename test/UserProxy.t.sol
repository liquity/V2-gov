// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

// import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {ILQTY} from "../src/interfaces/ILQTY.sol";

import {UserProxyFactory} from "./../src/UserProxyFactory.sol";
import {UserProxy} from "./../src/UserProxy.sol";

import {PermitParams} from "../src/utils/Types.sol";

contract UserProxyTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    UserProxyFactory private userProxyFactory;
    UserProxy private userProxy;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        userProxyFactory = new UserProxyFactory(address(lqty), address(lusd), stakingV1);
        userProxy = UserProxy(payable(userProxyFactory.deployUserProxy()));
    }

    function test_stake() public {
        vm.startPrank(user);
        lqty.approve(address(userProxy), 1e18);
        vm.stopPrank();

        vm.startPrank(address(userProxyFactory));
        userProxy.stake(user, 1e18);
        vm.stopPrank();
    }

    function test_stakeViaPermit() public {
        vm.startPrank(user);
        VmSafe.Wallet memory wallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        lqty.transfer(wallet.addr, 1e18);
        vm.stopPrank();

        vm.startPrank(wallet.addr);

        // check address
        userProxy = UserProxy(payable(userProxyFactory.deployUserProxy()));

        PermitParams memory permitParams = PermitParams({
            owner: wallet.addr,
            spender: address(userProxy),
            value: 1e18,
            deadline: block.timestamp + 86400,
            v: 0,
            r: "",
            s: ""
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wallet.privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ILQTY(address(lqty)).domainSeparator(),
                    keccak256(
                        abi.encode(
                            0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9,
                            permitParams.owner,
                            permitParams.spender,
                            permitParams.value,
                            0,
                            permitParams.deadline
                        )
                    )
                )
            )
        );

        permitParams.v = v;
        permitParams.r = r;
        permitParams.s = s;

        vm.stopPrank();

        vm.startPrank(user);
        lqty.approve(address(userProxy), 1e18);
        vm.stopPrank();

        // deposit 1 LQTY
        vm.startPrank(address(userProxyFactory));
        vm.expectRevert();
        userProxy.stakeViaPermit(user, 0.5e18, permitParams);
        userProxy.stakeViaPermit(wallet.addr, 0.5e18, permitParams);
        userProxy.stakeViaPermit(wallet.addr, 0.5e18, permitParams);
        vm.expectRevert();
        userProxy.stakeViaPermit(wallet.addr, 1, permitParams);
        vm.stopPrank();
    }

    function test_unstake() public {
        vm.startPrank(user);
        lqty.approve(address(userProxy), 1e18);
        vm.stopPrank();

        vm.startPrank(address(userProxyFactory));

        userProxy.stake(user, 1e18);

        (uint256 lqtyAmount, uint256 lusdAmount, uint256 ethAmount) = userProxy.unstake(0, user, user);
        assertEq(lqtyAmount, 0);
        assertEq(lusdAmount, 0);
        assertEq(ethAmount, 0);

        vm.warp(block.timestamp + 365 days);

        (lqtyAmount, lusdAmount, ethAmount) = userProxy.unstake(1e18, user, user);
        assertEq(lqtyAmount, 1e18);
        assertEq(lusdAmount, 0);
        assertEq(ethAmount, 0);

        vm.stopPrank();
    }
}
