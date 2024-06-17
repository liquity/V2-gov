// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {StakingV2} from "../src/StakingV2.sol";
import {VotingV2} from "../src/VotingV2.sol";
import {WAD, PermitParams} from "../src/Utils.sol";

interface ILQTY {
    function domainSeparator() external view returns (bytes32);
}

contract StakingV2Test is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0x64690353808dBcC843F95e30E071a0Ae6339EE1b);

    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant REGISTRATION_FEE = 0;
    uint256 private constant EPOCH_DURATION = 604800;

    StakingV2 private stakingV2;
    VotingV2 private voting;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        address _voting = vm.computeCreateAddress(address(this), 2);
        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1, _voting);
        voting = new VotingV2(address(stakingV2), address(lusd), MIN_CLAIM, MIN_ACCRUAL, REGISTRATION_FEE, block.timestamp, EPOCH_DURATION);
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

    function test_depositLQTYViaPermit() public {
        vm.startPrank(user);
        VmSafe.Wallet memory wallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        lqty.transfer(wallet.addr, 1e18);
        vm.stopPrank();
        vm.startPrank(wallet.addr);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

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

        // deposit 1 LQTY
        assertEq(stakingV2.depositLQTYViaPermit(1e18, permitParams), 1e18);
        assertEq(stakingV2.sharesByUser(wallet.addr), 1e18);
    }

    function test_currentShareRate() public payable {
        vm.warp(0);
        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1, address(0));
        assertEq(stakingV2.currentShareRate(), 1e18);

        vm.warp(1);
        assertGt(stakingV2.currentShareRate(), 1e18);

        vm.warp(365 days);
        assertEq(stakingV2.currentShareRate(), 2 * WAD);

        vm.warp(730 days);
        assertEq(stakingV2.currentShareRate(), 3 * WAD);

        vm.warp(1095 days);
        assertEq(stakingV2.currentShareRate(), 4 * WAD);
    }
}
