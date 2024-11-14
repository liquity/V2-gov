// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

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

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0,
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(
                governance.epoch(),
                user2,
                allocation.allocatedLQTY,
                allocation.voteOffset,
                allocation.isVeto,
                userState,
                initiativeState
            );
        }
        (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(totalAverageTimestamp, uint120(block.timestamp));
        (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
        assertEq(userLQTYAllocated, 1e18);
        assertEq(userAverageTimestamp, uint120(block.timestamp));

        {
            IGovernance.UserState memory userState2 =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation2 = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0,
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState2 = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState2, allocation2, initiativeState2);
        }

        (uint88 totalLQTYAllocated2, uint120 totalAverageTimestamp2) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated2, 1001e18);
        assertEq(totalAverageTimestamp2, block.timestamp);
        (uint88 userLQTYAllocated2, uint120 userAverageTimestamp2) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
        assertEq(userLQTYAllocated2, 1000e18);
        assertEq(userAverageTimestamp2, block.timestamp);

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();
        governance.setEpoch(2);

        vm.startPrank(address(governance));

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 2000e18, averageStakingTimestamp: uint32(1)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 2000e18,
                voteOffset: 0,
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 2001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(1),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);
        }

        (totalLQTYAllocated, totalAverageTimestamp) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated, 2001e18);
        assertEq(totalAverageTimestamp, 1);
        (userLQTYAllocated, userAverageTimestamp) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
        assertEq(userLQTYAllocated, 2000e18);
        assertEq(userAverageTimestamp, 1);

        governance.setEpoch(3);

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 2;
        claimData[0].prevLQTYAllocationEpoch = 2;
        claimData[0].prevTotalLQTYAllocationEpoch = 2;
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(claimData);
        assertGt(boldAmount, 999e18);
        assertGt(bribeTokenAmount, 999e18);
    }

    function test_onAfterAllocateLQTY_newEpoch_NoVetoToVeto() public {
        governance.setEpoch(1);
        vm.warp(governance.EPOCH_DURATION()); // warp to end of first epoch

        vm.startPrank(address(governance));

        // set user2 allocations like governance would using onAfterAllocateLQTY at epoch 1
        // sets avgTimestamp to current block.timestamp
        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0,
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);
            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        // set user2 allocations like governance would using onAfterAllocateLQTY at epoch 1
        // sets avgTimestamp to current block.timestamp
        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0,
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        // lusdHolder deposits bribes into the initiative
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(2);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to second epoch ts

        vm.startPrank(address(governance));

        // set allocation in initiative for user in epoch 1
        // sets avgTimestamp to current block.timestamp
        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0,
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 0,
                vetoLQTY: 1,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);
            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 0);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        // set allocation in initiative for user2 in epoch 1
        // sets avgTimestamp to current block.timestamp
        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0,
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 0,
                vetoLQTY: 1,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);
            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 0);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(3);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to third epoch ts

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 2;
        claimData[0].prevLQTYAllocationEpoch = 2;
        claimData[0].prevTotalLQTYAllocationEpoch = 2;
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(claimData);
        assertEq(boldAmount, 0, "boldAmount nonzero");
        assertEq(bribeTokenAmount, 0, "bribeTokenAmount nonzero");
    }

    function test_onAfterAllocateLQTY_newEpoch_VetoToNoVeto() public {
        governance.setEpoch(1);
        vm.warp(governance.EPOCH_DURATION()); // warp to end of first epoch

        vm.startPrank(address(governance));

        IGovernance.UserState memory userState =
            IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
        IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
            allocatedLQTY: 1e18,
            voteOffset: 0, // governance.epoch()
            isVeto: false
        });
        IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
            voteLQTY: 1e18,
            vetoLQTY: 0,
            averageStakingTimestampVoteLQTY: uint32(block.timestamp),
            averageStakingTimestampVetoLQTY: 0,
            lastEpochClaim: 0
        });
        bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

        (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(totalAverageTimestamp, uint120(block.timestamp));
        (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
        assertEq(userLQTYAllocated, 1e18);
        assertEq(userAverageTimestamp, uint120(block.timestamp));

        IGovernance.UserState memory userStateVeto =
            IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
        IGovernance.UserInitiativeAllocation memory allocationVeto = IGovernance.UserInitiativeAllocation({
            allocatedLQTY: 1000e18,
            voteOffset: 0, // governance.epoch()
            isVeto: true
        });
        IGovernance.InitiativeState memory initiativeStateVeto = IGovernance.InitiativeState({
            voteLQTY: 1e18,
            vetoLQTY: 1000e18,
            averageStakingTimestampVoteLQTY: uint32(block.timestamp),
            averageStakingTimestampVetoLQTY: uint32(block.timestamp),
            lastEpochClaim: 0
        });
        bribeInitiative.onAfterAllocateLQTY(
            governance.epoch(), user, userStateVeto, allocationVeto, initiativeStateVeto
        );

        (uint88 totalLQTYAllocatedAfterVeto, uint120 totalAverageTimestampAfterVeto) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocatedAfterVeto, 1e18);
        assertEq(totalAverageTimestampAfterVeto, uint120(block.timestamp));
        (uint88 userLQTYAllocatedAfterVeto, uint120 userAverageTimestampAfterVeto) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
        assertEq(userLQTYAllocatedAfterVeto, 0);
        assertEq(userAverageTimestampAfterVeto, uint120(block.timestamp));

        governance.setEpoch(2);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to second epoch ts

        IGovernance.UserState memory userStateNewEpoch =
            IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint32(block.timestamp)});
        IGovernance.UserInitiativeAllocation memory allocationNewEpoch = IGovernance.UserInitiativeAllocation({
            allocatedLQTY: 1,
            voteOffset: 0, // governance.epoch()
            isVeto: true
        });
        IGovernance.InitiativeState memory initiativeStateNewEpoch = IGovernance.InitiativeState({
            voteLQTY: 1e18,
            vetoLQTY: 1,
            averageStakingTimestampVoteLQTY: uint32(block.timestamp),
            averageStakingTimestampVetoLQTY: uint32(block.timestamp),
            lastEpochClaim: 0
        });
        bribeInitiative.onAfterAllocateLQTY(
            governance.epoch(), user, userStateNewEpoch, allocationNewEpoch, initiativeStateNewEpoch
        );

        (uint88 totalLQTYAllocatedNewEpoch, uint120 totalAverageTimestampNewEpoch) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocatedNewEpoch, 1e18);
        assertEq(totalAverageTimestampNewEpoch, uint120(block.timestamp));
        (uint88 userLQTYAllocatedNewEpoch, uint120 userAverageTimestampNewEpoch) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
        assertEq(userLQTYAllocatedNewEpoch, 0);
        assertEq(userAverageTimestampNewEpoch, uint120(block.timestamp));

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        vm.startPrank(address(governance));

        governance.setEpoch(3);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to third epoch ts

        IGovernance.UserState memory userStateNewEpoch3 =
            IGovernance.UserState({allocatedLQTY: 2000e18, averageStakingTimestamp: uint32(block.timestamp)});
        IGovernance.UserInitiativeAllocation memory allocationNewEpoch3 = IGovernance.UserInitiativeAllocation({
            allocatedLQTY: 2000e18,
            voteOffset: 0, // governance.epoch()
            isVeto: false
        });
        IGovernance.InitiativeState memory initiativeStateNewEpoch3 = IGovernance.InitiativeState({
            voteLQTY: 2001e18,
            vetoLQTY: 0,
            averageStakingTimestampVoteLQTY: uint32(block.timestamp),
            averageStakingTimestampVetoLQTY: 0,
            lastEpochClaim: 0
        });
        bribeInitiative.onAfterAllocateLQTY(
            governance.epoch(), user, userStateNewEpoch3, allocationNewEpoch3, initiativeStateNewEpoch3
        );

        (uint88 totalLQTYAllocatedNewEpoch3, uint120 totalAverageTimestampNewEpoch3) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocatedNewEpoch3, 2001e18);
        assertEq(totalAverageTimestampNewEpoch3, uint120(block.timestamp));
        (uint88 userLQTYAllocatedNewEpoch3, uint120 userAverageTimestampNewEpoch3) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
        assertEq(userLQTYAllocatedNewEpoch3, 2000e18);
        assertEq(userAverageTimestampNewEpoch3, uint120(block.timestamp));

        governance.setEpoch(4);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to fourth epoch ts

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

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 1000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(2);

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(3);

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }
    }

    function test_onAfterAllocateLQTY_sameEpoch_NoVetoToNoVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(1);
        vm.warp(governance.EPOCH_DURATION()); // warp to end of first epoch

        vm.startPrank(address(governance));

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 1000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 2000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 2000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 2001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 2001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 2000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(2);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to second epoch ts

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
        vm.warp(governance.EPOCH_DURATION()); // warp to end of first epoch

        vm.startPrank(address(governance));

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 1000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(2);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to second epoch ts

        vm.startPrank(address(user));

        BribeInitiative.ClaimData[] memory claimData = new BribeInitiative.ClaimData[](1);
        claimData[0].epoch = 1;
        claimData[0].prevLQTYAllocationEpoch = 1;
        claimData[0].prevTotalLQTYAllocationEpoch = 1;
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(claimData);
        assertEq(boldAmount, 0);
        assertEq(bribeTokenAmount, 0);
    }

    function test_onAfterAllocateLQTY_sameEpoch_VetoToNoVeto() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1000e18);
        lusd.approve(address(bribeInitiative), 1000e18);
        bribeInitiative.depositBribe(1000e18, 1000e18, governance.epoch() + 1);
        vm.stopPrank();

        governance.setEpoch(1);
        vm.warp(governance.EPOCH_DURATION()); // warp to end of first epoch

        vm.startPrank(address(governance));

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 1000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 2000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 2000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 2001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 2001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 2000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        governance.setEpoch(2);
        vm.warp(block.timestamp + governance.EPOCH_DURATION()); // warp to second epoch ts

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

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
            assertEq(userLQTYAllocated, 1e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1000e18, averageStakingTimestamp: uint32(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1000e18,
                voteOffset: 0, // governance.epoch()
                isVeto: false
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1001e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint32(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1001e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 1000e18);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 1, averageStakingTimestamp: uint120(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 1,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint120(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint120(block.timestamp));
        }

        {
            IGovernance.UserState memory userState =
                IGovernance.UserState({allocatedLQTY: 2, averageStakingTimestamp: uint120(block.timestamp)});
            IGovernance.UserInitiativeAllocation memory allocation = IGovernance.UserInitiativeAllocation({
                allocatedLQTY: 2,
                voteOffset: 0, // governance.epoch()
                isVeto: true
            });
            IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
                voteLQTY: 1e18,
                vetoLQTY: 0,
                averageStakingTimestampVoteLQTY: uint120(block.timestamp),
                averageStakingTimestampVetoLQTY: 0,
                lastEpochClaim: 0
            });
            bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, userState, allocation, initiativeState);

            (uint88 totalLQTYAllocated, uint120 totalAverageTimestamp) =
                bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
            assertEq(totalLQTYAllocated, 1e18);
            assertEq(totalAverageTimestamp, uint120(block.timestamp));
            (uint88 userLQTYAllocated, uint120 userAverageTimestamp) =
                bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch());
            assertEq(userLQTYAllocated, 0);
            assertEq(userAverageTimestamp, uint32(block.timestamp));
        }
    }

    // function test_onAfterAllocateLQTY() public {
    //     governance.setEpoch(1);

    //     vm.startPrank(address(governance));

    //     // first total deposit, first user deposit
    //     bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
    //     assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1000e18);
    //     assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18);

    //     // second total deposit, second user deposit
    //     bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user, 1000e18, 0);
    //     assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 1000e18); // should stay the same
    //     assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user, governance.epoch()), 1000e18); // should stay the same

    //     // third total deposit, first user deposit
    //     bribeInitiative.onAfterAllocateLQTY(governance.epoch(), user2, 1000e18, 0);
    //     assertEq(bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch()), 2000e18);
    //     assertEq(bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch()), 1000e18);

    //     vm.stopPrank();
    // }
}
