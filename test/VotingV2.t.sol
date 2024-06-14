// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {console} from "forge-std/console.sol";

import {StakingV2} from "../src/StakingV2.sol";
import {VotingV2} from "../src/VotingV2.sol";
import {Collector} from "../src/Collector.sol";

contract VotingV2Test is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0x64690353808dBcC843F95e30E071a0Ae6339EE1b);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);

    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;

    VotingV2 private voting;
    StakingV2 private stakingV2;
    Collector private collector;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        address _voting = vm.computeCreateAddress(address(this), 3);
        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1, _voting);
        collector = new Collector(address(lusd), address(_voting));
        voting = new VotingV2(address(stakingV2), address(lusd), address(collector), MIN_CLAIM, MIN_ACCRUAL);
    }

    function test_epoch() public {
        assertEq(voting.epoch(), 1);

        vm.warp(block.timestamp + 7 days - 1);
        assertEq(voting.epoch(), 1);

        vm.warp(block.timestamp + 1);
        assertEq(voting.epoch(), 2);

        vm.warp(block.timestamp + 3653 days - 7 days);
        assertEq(voting.epoch(), 522); // number of weeks + 1
    }

    function test_sharesToVotes() public {
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 0);

        vm.warp(block.timestamp + 365 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 1e18);

        vm.warp(block.timestamp + 730 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 3e18);

        vm.warp(block.timestamp + 1095 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 6e18);
    }

    function test_calculateVotingThreshold() public {
        voting = new VotingV2(address(stakingV2), address(lusd), address(collector), MIN_CLAIM, MIN_ACCRUAL);

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        VotingV2.Snapshot memory snapshot = VotingV2.Snapshot(1e18, 1);
        vm.store(address(voting), bytes32(uint256(2)), bytes32(abi.encode(snapshot)));
        (uint240 votes,) = voting.votesSnapshot();
        assertEq(votes, 1e18);

        uint256 boldAccrued = 1000e18;
        vm.store(address(lusd), keccak256(abi.encode(address(voting), 2)), bytes32(abi.encode(boldAccrued)));
        assertEq(lusd.balanceOf(address(voting)), 1000e18);

        assertEq(voting.calculateVotingThreshold(), MIN_CLAIM / 1000);

        // check that votingThreshold is 4% of votes of previous epoch
        voting = new VotingV2(address(stakingV2), address(lusd), address(collector), 10e18, 10e18);

        snapshot = VotingV2.Snapshot(10000e18, 1);
        vm.store(address(voting), bytes32(uint256(2)), bytes32(abi.encode(snapshot)));
        (votes,) = voting.votesSnapshot();
        assertEq(votes, 10000e18);

        boldAccrued = 1000e18;
        vm.store(address(lusd), keccak256(abi.encode(address(voting), 2)), bytes32(abi.encode(boldAccrued)));
        assertEq(lusd.balanceOf(address(voting)), 1000e18);

        assertEq(voting.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    function test_registerInitiative() public {
        voting.registerInitiative(initiative);
        assertEq(voting.initiativesRegistered(initiative), block.timestamp);
    }

    function test_allocateShares() public {
        voting.registerInitiative(initiative);

        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(stakingV2.depositLQTY(1e18), 1e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory diffAllocations = new int256[](1);
        diffAllocations[0] = 1e18;
        int256[] memory diffVetos = new int256[](1);

        voting.allocateShares(initiatives, diffAllocations, diffVetos);
        assertEq(voting.qualifyingShares(), 1e18);
        assertEq(voting.sharesAllocatedByUser(user), 1e18);

        vm.expectRevert("StakingV2: insufficient-unallocated-shares");

        stakingV2.withdrawShares(1e18);
        initiatives[0] = initiative;
        diffAllocations[0] = -1e18;

        voting.allocateShares(initiatives, diffAllocations, diffVetos);
        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        vm.stopPrank();
    }

    function test_claimForInitiative() public {
        voting.registerInitiative(initiative);

        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        assertEq(stakingV2.depositLQTY(1000e18), 1000e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(voting), 1000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory diffAllocations = new int256[](1);
        diffAllocations[0] = 1000e18;
        int256[] memory diffVetos = new int256[](1);

        voting.allocateShares(initiatives, diffAllocations, diffVetos);
        assertEq(voting.qualifyingShares(), 1000e18);
        assertEq(voting.sharesAllocatedByUser(user), 1000e18);

        vm.warp(block.timestamp + voting.EPOCH_DURATION() + 1);

        assertGt(voting.claimForInitiative(initiative), 0);
        assertEq(voting.claimForInitiative(initiative), 0);

        vm.stopPrank();
    }
}
