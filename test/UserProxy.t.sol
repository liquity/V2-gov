// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {ILQTY} from "../src/interfaces/ILQTY.sol";
import {ILUSD} from "../src/interfaces/ILUSD.sol";
import {ILQTYStaking} from "../src/interfaces/ILQTYStaking.sol";

import {UserProxyFactory} from "./../src/UserProxyFactory.sol";
import {UserProxy} from "./../src/UserProxy.sol";

import {PermitParams} from "../src/utils/Types.sol";

import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";
import "./constants.sol";

abstract contract UserProxyTest is Test, MockStakingV1Deployer {
    ILQTY internal lqty;
    ILUSD internal lusd;
    ILQTYStaking internal stakingV1;

    address internal constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);

    UserProxyFactory private userProxyFactory;
    UserProxy private userProxy;

    function setUp() public virtual {
        userProxyFactory = new UserProxyFactory(address(lqty), address(lusd), address(stakingV1));
        userProxy = UserProxy(payable(userProxyFactory.deployUserProxy()));
    }

    function _addLUSDGain(uint256 amount) internal virtual;
    function _addETHGain(uint256 amount) internal virtual;

    function test_stake() public {
        vm.startPrank(user);
        lqty.approve(address(userProxy), 1e18);
        vm.stopPrank();

        vm.startPrank(address(userProxyFactory));
        userProxy.stake(1e18, user, false, address(0));
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
        userProxy.stakeViaPermit(0.5e18, user, permitParams, false, address(0));
        userProxy.stakeViaPermit(0.5e18, wallet.addr, permitParams, false, address(0));
        userProxy.stakeViaPermit(0.5e18, wallet.addr, permitParams, false, address(0));
        vm.expectRevert();
        userProxy.stakeViaPermit(1, wallet.addr, permitParams, false, address(0));
        vm.stopPrank();
    }

    function test_unstake() public {
        vm.startPrank(user);
        lqty.approve(address(userProxy), 1e18);
        vm.stopPrank();

        vm.startPrank(address(userProxyFactory));

        userProxy.stake(1e18, user, false, address(0));

        (,, uint256 lusdAmount,, uint256 ethAmount,) = userProxy.unstake(0, true, user);
        assertEq(lusdAmount, 0);
        assertEq(ethAmount, 0);

        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        _addETHGain(stakingV1.totalLQTYStaked());
        _addLUSDGain(stakingV1.totalLQTYStaked());

        vm.startPrank(address(userProxyFactory));

        (,, lusdAmount,, ethAmount,) = userProxy.unstake(1e18, true, user);
        assertEq(lusdAmount, 1e18);
        assertEq(ethAmount, 1e18);

        vm.stopPrank();
    }
}

contract MockedUserProxyTest is UserProxyTest {
    MockERC20Tester private mockLQTY;
    MockERC20Tester private mockLUSD;
    MockStakingV1 private mockStakingV1;

    function setUp() public override {
        (mockStakingV1, mockLQTY, mockLUSD) = deployMockStakingV1();
        mockLQTY.mint(user, 1e18);

        lqty = mockLQTY;
        lusd = mockLUSD;
        stakingV1 = mockStakingV1;

        super.setUp();
    }

    function _addLUSDGain(uint256 amount) internal override {
        mockLUSD.mint(address(this), amount);
        mockLUSD.approve(address(mockStakingV1), amount);
        mockStakingV1.mock_addLUSDGain(amount);
    }

    function _addETHGain(uint256 amount) internal override {
        deal(address(this), address(this).balance + amount);
        mockStakingV1.mock_addETHGain{value: amount}();
    }
}

contract ForkedUserProxyTest is UserProxyTest {
    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        lqty = ILQTY(MAINNET_LQTY);
        lusd = ILUSD(MAINNET_LUSD);
        stakingV1 = ILQTYStaking(MAINNET_LQTY_STAKING);

        super.setUp();
    }

    function _addLUSDGain(uint256 amount) internal override {
        vm.prank(MAINNET_BORROWER_OPERATIONS);
        stakingV1.increaseF_LUSD(amount);

        vm.prank(MAINNET_BORROWER_OPERATIONS);
        lusd.mint(address(stakingV1), amount);
    }

    function _addETHGain(uint256 amount) internal override {
        deal(MAINNET_ACTIVE_POOL, MAINNET_ACTIVE_POOL.balance + amount);
        vm.prank(MAINNET_ACTIVE_POOL);
        (bool success,) = address(stakingV1).call{value: amount}("");
        assert(success);

        vm.prank(MAINNET_TROVE_MANAGER);
        stakingV1.increaseF_ETH(amount);
    }
}
