// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockGovernance} from "./mocks/MockGovernance.sol";

// new epoch:
//   no veto to no veto: insert new user allocation, add and sub from total allocation
// (prevVoteLQTY == 0 || prevVoteLQTY != 0) && _vetoLQTY == 0

//   no veto to veto: insert new 0 user allocation, sub from total allocation
// (prevVoteLQTY == 0 || prevVoteLQTY != 0) && _vetoLQTY != 0

//   veto to no veto: insert new user allocation, add to total allocation
// prevVoteLQTY == 0 && _vetoLQTY == 0

//   veto to veto: insert new 0 user allocation, do nothing to total allocation
// prevVoteLQTY == 0 && _vetoLQTY != 0

// same epoch:
//   no veto to no veto: update user allocation, add and sub from total allocation
//   no veto to veto: set 0 user allocation, sub from total allocation
//   veto to no veto: update user allocation, add to total allocation
//   veto to veto: set 0 user allocation, do nothing to total allocation

contract BribeInitiativeAllocateTest is Test {
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    MockGovernance private governance;
    BribeInitiative private bribeInitiative;

    function setUp() public {
        lqty = deployMockERC20("Liquity", "LQTY", 18);
        lusd = deployMockERC20("Liquity USD", "LUSD", 18);

        vm.store(address(lqty), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));
        vm.store(address(lusd), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));

        stakingV1 = address(new MockStakingV1(address(lqty)));

        governance = new MockGovernance();

        bribeInitiative = new BribeInitiative(address(governance), address(lusd), address(lqty));
    }

    function test_onAfterAllocateLQTY_newEpoch_NoVetoToNoVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();
        governance.setEpoch(2);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 0);

        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 2000e18);

        governance.setEpoch(3);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 2;
        claimData[0].prevLQTYAllocationEpoch = 2;
        claimData[0].prevTotalLQTYAllocationEpoch = 2;
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_newEpoch_NoVetoToVeto() public {
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(2);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 0);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 0);

        governance.setEpoch(3);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 2;
        claimData[0].prevLQTYAllocationEpoch = 2;
        claimData[0].prevTotalLQTYAllocationEpoch = 2;
        vm.expectRevert("BribeInitiative: invalid-prev-lqty-allocation-epoch"); // nothing to claim
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_newEpoch_VetoToNoVeto() public {
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        governance.setEpoch(2);
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        vm.startPrank(address(governance));

        governance.setEpoch(3);
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 2000e18);

        governance.setEpoch(4);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 3;
        claimData[0].prevLQTYAllocationEpoch = 3;
        claimData[0].prevTotalLQTYAllocationEpoch = 3;
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_newEpoch_VetoToVeto() public {
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        governance.setEpoch(2);
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        governance.setEpoch(3);
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);
    }

    function test_onAfterAllocateLQTY_sameEpoch_NoVetoToNoVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 2000e18);

        governance.setEpoch(2);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 1;
        claimData[0].prevLQTYAllocationEpoch = 1;
        claimData[0].prevTotalLQTYAllocationEpoch = 1;
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_sameEpoch_NoVetoToVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        governance.setEpoch(2);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 1;
        claimData[0].prevLQTYAllocationEpoch = 1;
        claimData[0].prevTotalLQTYAllocationEpoch = 1;
        vm.expectRevert("BribeInitiative: invalid-prev-lqty-allocation-epoch"); // nothing to claim
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_sameEpoch_VetoToNoVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 2000e18);

        governance.setEpoch(2);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 1;
        claimData[0].prevLQTYAllocationEpoch = 1;
        claimData[0].prevTotalLQTYAllocationEpoch = 1;
        bribeInitiative.claimBribes(claimData);
    }

    function test_onAfterAllocateLQTY_sameEpoch_VetoToVeto() public {
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1001e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 2000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);

        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 1);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 0);
    }

    function test_onAfterAllocateLQTY() public {
        governance.setEpoch(1);

        vm.startPrank(address(governance));

        // first total deposit, first user deposit
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1000e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

        // second total deposit, second user deposit
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1000e18); // should stay the same
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18); // should stay the same

        // third total deposit, first user deposit
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1000e18, 0);
        assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2000e18);
        assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1000e18);

        vm.stopPrank();
    }
}
