// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {StakingV2} from "../src/StakingV2.sol";
import {Voting} from "../src/Voting.sol";

contract StakingV2Test is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0x64690353808dBcC843F95e30E071a0Ae6339EE1b);

    address private constant initiative = address(0x1);

    Voting private voting;
    StakingV2 private stakingV2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1);
        voting = new Voting(address(stakingV2));
        stakingV2.setVoting(address(voting));
    }

    function test_votingPower() public {
        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(stakingV2.depositLQTY(1e18), 1e18);
        assertEq(stakingV2.sharesByUser(user), 1e18);

        assertEq(voting.votingPower(user), 0);

        vm.warp(block.timestamp + 365 days);
        assertEq(voting.votingPower(user), 1e18);

        vm.warp(block.timestamp + 730 days);
        assertEq(voting.votingPower(user), 3e18);

        vm.warp(block.timestamp + 1095 days);
        assertEq(voting.votingPower(user), 6e18);

        vm.stopPrank();
    }

    function test_registerInitiative() public {
        voting.registerInitiative(initiative);
        assertEq(voting.initiatives(initiative), address(this));
    }

    function test_vote() public {
        voting.registerInitiative(initiative);

        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(stakingV2.depositLQTY(1e18), 1e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(voting.votesAllocated(), 0);
        assertEq(voting.votesAllocatedByUser(user), 0);

        voting.vote(initiative, 1e18);
        assertEq(voting.votesAllocated(), 1e18);
        assertEq(voting.votesAllocatedByUser(user), 1e18);

        vm.stopPrank();
    }
}
