// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "../src/interfaces/IBribeInitiative.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {MockStakingV1} from "./mocks/MockStakingV1.sol";

contract BribeInitiativeTest is Test {
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    address private constant user1 = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address private user3 = makeAddr("user3");
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);
    address private constant initiative2 = address(0x2);
    address private constant initiative3 = address(0x3);

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant REGISTRATION_WARM_UP_PERIOD = 4;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 7 days; // 7 days
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    BribeInitiative private bribeInitiative;

    function setUp() public {
        lqty = deployMockERC20("Liquity", "LQTY", 18);
        lusd = deployMockERC20("Liquity USD", "LUSD", 18);

        vm.store(address(lqty), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10_000_000e18)));
        vm.store(address(lusd), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10_000_000e18)));
        vm.store(address(lqty), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10_000_000e18)));
        vm.store(address(lusd), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10_000_000e18)));

        stakingV1 = address(new MockStakingV1(address(lqty)));

        bribeInitiative = new BribeInitiative(
            address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(lusd),
            address(lqty)
        );

        initialInitiatives.push(address(bribeInitiative));

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        vm.startPrank(lusdHolder);
        lqty.transfer(user1, 1_000_000e18);
        lusd.transfer(user1, 1_000_000e18);
        lqty.transfer(user2, 1_000_000e18);
        lusd.transfer(user2, 1_000_000e18);
        lqty.transfer(user3, 1_000_000e18);
        lusd.transfer(user3, 1_000_000e18);
        vm.stopPrank();
    }

    // test total allocation vote case
    function test_totalLQTYAllocatedByEpoch_vote() public {
        // staking LQTY into governance for user1 in first epoch
        _stakeLQTY(user1, 10e18);

        // fast forward to second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // allocate LQTY to the bribeInitiative
        _allocateLQTY(user1, 10e18, 0);
        // total LQTY allocated for this epoch should increase
        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated, 10e18);
    }

    // test total allocation veto case
    function test_totalLQTYAllocatedByEpoch_veto() public {
        _stakeLQTY(user1, 10e18);

        // fast forward to second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // allocate LQTY to veto bribeInitiative
        _allocateLQTY(user1, 0, 10e18);
        // total LQTY allocated for this epoch should not increase
        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated, 0);
    }

    // user1 allocates multiple times in different epochs
    function test_allocating_same_initiative_multiple_epochs() public {
        _stakeLQTY(user1, 10e18);

        // fast forward to second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // allocate LQTY to the bribeInitiative
        _allocateLQTY(user1, 5e18, 0);

        // total LQTY allocated for this epoch should increase
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        // fast forward to third epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 5e18, 0);

        // total LQTY allocated for this epoch should not change
        (uint88 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 5e18);
        assertEq(userLQTYAllocated1, 5e18);
    }

    // user1 allocates multiple times in same epoch
    function test_totalLQTYAllocatedByEpoch_vote_same_epoch() public {
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 5e18);
        assertEq(userLQTYAllocated2, 5e18);
    }

    function test_allocation_stored_in_list() public {
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        console2.log("current governance epoch: ", governance.epoch());
        // user's linked-list should be updated to have a value for the current epoch
        (uint88 allocatedAtEpoch,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        console2.log("allocatedAtEpoch: ", allocatedAtEpoch);
    }

    // test total allocation by multiple users in multiple epochs
    function test_totalLQTYAllocatedByEpoch_vote_multiple_epochs() public {
        _stakeLQTY(user1, 10e18);
        _stakeLQTY(user2, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 10e18, 0);
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        // user2 allocates in second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // user allocations should be disjoint because they're in separate epochs
        _allocateLQTY(user2, 10e18, 0);
        (uint88 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
        assertEq(totalLQTYAllocated2, 20e18);
        assertEq(userLQTYAllocated2, 10e18);
    }

    // test total allocations for multiple users in the same epoch
    function test_totalLQTYAllocatedByEpoch_vote_same_epoch_multiple() public {
        _stakeLQTY(user1, 10e18);
        _stakeLQTY(user2, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 10e18, 0);
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        _allocateLQTY(user2, 10e18, 0);
        (uint88 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
        assertEq(totalLQTYAllocated2, 20e18);
        assertEq(userLQTYAllocated2, 10e18);
    }

    // test total allocation doesn't grow from start to end of epoch
    function test_totalLQTYAllocatedByEpoch_growth() public {
        _stakeLQTY(user1, 10e18);
        _stakeLQTY(user2, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 10e18, 0);
        (uint88 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);

        // warp to the end of the epoch
        vm.warp(block.timestamp + (EPOCH_VOTING_CUTOFF - 1));

        (uint88 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated2, 10e18);
    }

    // test depositing bribe
    function test_depositBribe_success() public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1e18);
        lusd.approve(address(bribeInitiative), 1e18);
        bribeInitiative.depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.stopPrank();
    }

    // user that votes in an epoch that has bribes allocated to it will receive bribes on claiming
    function test_claimBribes() public {
        // =========== epoch 1 ==================
        // user stakes in epoch 1
        _stakeLQTY(user1, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        uint16 depositedBribe = governance.epoch() + 1;

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // user votes on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);

        // =========== epoch 5 ==================
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));
        assertEq(5, governance.epoch(), "not in epoch 5");

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, depositedBribe, depositedBribe, depositedBribe);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
    }

    // user that votes in an epoch that has bribes allocated to it will receive bribes on claiming
    // forge test --match-test test_high_deny_last_claim -vv
    function test_high_deny_last_claim() public {
        /// @audit Overflow due to rounding error in bribes total math vs user math
        // See: `test_we_can_compare_votes_and_vetos`
        // And `test_crit_user_can_dilute_total_votes`
        vm.warp(block.timestamp + EPOCH_DURATION);

        // =========== epoch 1 ==================
        // user stakes in epoch 1
        vm.warp(block.timestamp + 5);
        _stakeLQTY(user1, 1e18);
        vm.warp(block.timestamp + 7);
        _stakeLQTY(user2, 1e18);

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch());
        _allocateLQTY(user1, 1e18, 0);
        _allocateLQTY(user2, 1, 0);
        _allocateLQTY(user2, 0, 0);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION); // Needs to cause rounding error
        assertEq(3, governance.epoch(), "not in epoch 2");

        // user votes on bribeInitiative

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) = _claimBribe(user1, 2, 2, 2);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
    }

    // check that bribes deposited after user votes can be claimed
    function test_claimBribes_deposited_after_vote() public {
        // =========== epoch 1 ==================
        // user stakes in epoch 1
        _stakeLQTY(user1, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // user votes on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 4
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 5 ==================
        // warp ahead two epochs because bribes can't be claimed in current epoch
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));
        assertEq(5, governance.epoch(), "not in epoch 5");

        // check amount of bribes in epoch 3
        (uint128 boldAmountFromStorage, uint128 bribeTokenAmountFromStorage) =
            IBribeInitiative(bribeInitiative).bribeByEpoch(governance.epoch() - 2);
        assertEq(boldAmountFromStorage, 1e18, "boldAmountFromStorage != 1e18");
        assertEq(bribeTokenAmountFromStorage, 1e18, "bribeTokenAmountFromStorage != 1e18");

        // check amount of bribes in epoch 4
        (boldAmountFromStorage, bribeTokenAmountFromStorage) =
            IBribeInitiative(bribeInitiative).bribeByEpoch(governance.epoch() - 1);
        assertEq(boldAmountFromStorage, 1e18, "boldAmountFromStorage != 1e18");
        assertEq(bribeTokenAmountFromStorage, 1e18, "bribeTokenAmountFromStorage != 1e18");

        // user should receive bribe from their allocated stake for each epoch

        // user claims for epoch 3
        uint16 claimEpoch = governance.epoch() - 2; // claim for epoch 3
        uint16 prevAllocationEpoch = governance.epoch() - 2; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);

        // user claims for epoch 4
        claimEpoch = governance.epoch() - 1; // claim for epoch 4
        prevAllocationEpoch = governance.epoch() - 2; // epoch 3
        (boldAmount, bribeTokenAmount) = _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
    }

    // check that received bribes are proportional to user's stake in the initiative
    function test_claimedBribes_fraction() public {
        // =========== epoch 1 ==================
        // both users stake in epoch 1
        _stakeLQTY(user1, 1e18);
        _stakeLQTY(user2, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // users both vote on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);
        _allocateLQTY(user2, 1e18, 0);

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(4, governance.epoch(), "not in epoch 4");

        // user claims for epoch 3
        uint16 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint16 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);

        // calculate user share of total allocation for initiative for the given epoch as percentage
        (uint88 userLqtyAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, 3);
        (uint88 totalLqtyAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(3);
        uint256 userShareOfTotalAllocated = uint256((userLqtyAllocated * 10_000) / totalLqtyAllocated);
        console2.log("userLqtyAllocated: ", userLqtyAllocated);
        console2.log("totalLqtyAllocated: ", totalLqtyAllocated);

        // calculate user received bribes as share of total bribes as percentage
        (uint128 boldAmountForEpoch, uint128 bribeTokenAmountForEpoch) = bribeInitiative.bribeByEpoch(3);
        uint256 userShareOfTotalBoldForEpoch = (boldAmount * 10_000) / uint256(boldAmountForEpoch);
        uint256 userShareOfTotalBribeForEpoch = (bribeTokenAmount * 10_000) / uint256(bribeTokenAmountForEpoch);

        // check that they're equivalent
        assertEq(
            userShareOfTotalAllocated,
            userShareOfTotalBoldForEpoch,
            "userShareOfTotalAllocated != userShareOfTotalBoldForEpoch"
        );
        assertEq(
            userShareOfTotalAllocated,
            userShareOfTotalBribeForEpoch,
            "userShareOfTotalAllocated != userShareOfTotalBribeForEpoch"
        );
    }

    function test_claimedBribes_fraction_fuzz(uint88 user1StakeAmount, uint88 user2StakeAmount, uint88 user3StakeAmount)
        public
    {
        // =========== epoch 1 ==================
        user1StakeAmount = uint88(bound(uint256(user1StakeAmount), 1, lqty.balanceOf(user1)));
        user2StakeAmount = uint88(bound(uint256(user2StakeAmount), 1, lqty.balanceOf(user2)));
        user3StakeAmount = uint88(bound(uint256(user3StakeAmount), 1, lqty.balanceOf(user3)));

        // all users stake in epoch 1
        _stakeLQTY(user1, user1StakeAmount);
        _stakeLQTY(user2, user2StakeAmount);
        _stakeLQTY(user3, user3StakeAmount);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // users all vote on bribeInitiative
        _allocateLQTY(user1, int88(user1StakeAmount), 0);
        _allocateLQTY(user2, int88(user2StakeAmount), 0);
        _allocateLQTY(user3, int88(user3StakeAmount), 0);

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(4, governance.epoch(), "not in epoch 4");

        // all users claim bribes for epoch 3
        uint16 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint16 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (uint256 boldAmount1, uint256 bribeTokenAmount1) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        (uint256 boldAmount2, uint256 bribeTokenAmount2) =
            _claimBribe(user2, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        (uint256 boldAmount3, uint256 bribeTokenAmount3) =
            _claimBribe(user3, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);

        // calculate user share of total allocation for initiative for the given epoch as percentage
        uint256 userShareOfTotalAllocated1 = _getUserShareOfAllocationAsPercentage(user1, 3);
        uint256 userShareOfTotalAllocated2 = _getUserShareOfAllocationAsPercentage(user2, 3);
        uint256 userShareOfTotalAllocated3 = _getUserShareOfAllocationAsPercentage(user3, 3);

        // calculate user received bribes as share of total bribes as percentage
        (uint256 userShareOfTotalBoldForEpoch1, uint256 userShareOfTotalBribeForEpoch1) =
            _getBribesAsPercentageOfTotal(3, boldAmount1, bribeTokenAmount1);
        (uint256 userShareOfTotalBoldForEpoch2, uint256 userShareOfTotalBribeForEpoch2) =
            _getBribesAsPercentageOfTotal(3, boldAmount2, bribeTokenAmount2);
        (uint256 userShareOfTotalBoldForEpoch3, uint256 userShareOfTotalBribeForEpoch3) =
            _getBribesAsPercentageOfTotal(3, boldAmount3, bribeTokenAmount3);

        // check that they're equivalent
        // user1
        assertEq(
            userShareOfTotalAllocated1,
            userShareOfTotalBoldForEpoch1,
            "userShareOfTotalAllocated1 != userShareOfTotalBoldForEpoch1"
        );
        assertEq(
            userShareOfTotalAllocated1,
            userShareOfTotalBribeForEpoch1,
            "userShareOfTotalAllocated1 != userShareOfTotalBribeForEpoch1"
        );
        // user2
        assertEq(
            userShareOfTotalAllocated2,
            userShareOfTotalBoldForEpoch2,
            "userShareOfTotalAllocated2 != userShareOfTotalBoldForEpoch2"
        );
        assertEq(
            userShareOfTotalAllocated2,
            userShareOfTotalBribeForEpoch2,
            "userShareOfTotalAllocated2 != userShareOfTotalBribeForEpoch2"
        );
        // user3
        assertEq(
            userShareOfTotalAllocated3,
            userShareOfTotalBoldForEpoch3,
            "userShareOfTotalAllocated3 != userShareOfTotalBoldForEpoch3"
        );
        assertEq(
            userShareOfTotalAllocated3,
            userShareOfTotalBribeForEpoch3,
            "userShareOfTotalAllocated3 != userShareOfTotalBribeForEpoch3"
        );
    }

    // only users that voted receive bribe, vetoes shouldn't receive anything
    function test_only_voter_receives_bribes() public {
        // =========== epoch 1 ==================
        // both users stake in epoch 1
        _stakeLQTY(user1, 1e18);
        _stakeLQTY(user2, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // user1 votes on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);
        // user2 vetos on bribeInitiative
        _allocateLQTY(user2, 0, 1e18);

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(4, governance.epoch(), "not in epoch 4");

        // user claims for epoch 3
        uint16 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint16 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18, "voter doesn't receive full bold bribe amount");
        assertEq(bribeTokenAmount, 1e18, "voter doesn't receive full bribe amount");

        // user2 should receive no bribes if they try to claim
        claimEpoch = governance.epoch() - 1; // claim for epoch 3
        prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (boldAmount, bribeTokenAmount) = _claimBribe(user2, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 0, "vetoer receives bold bribe amount");
        assertEq(bribeTokenAmount, 0, "vetoer receives bribe amount");
    }

    // TODO: check favorability of splitting allocation between different initiative/epochs
    // @audit doesn't seem like it makes it more favorable because user still withdraws full bribe amount
    // forge test --match-test test_splitting_allocation -vv
    function test_splitting_allocation() public {
        // =========== epoch 1 ==================
        // user stakes half in epoch 1
        int88 lqtyAmount = 2e18;
        _stakeLQTY(user1, uint88(lqtyAmount / 2));

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 4
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        uint16 epochToClaimFor = governance.epoch() + 1;

        // user votes on bribeInitiative with half
        _allocateLQTY(user1, lqtyAmount / 2, 0);
        (, uint32 averageStakingTimestamp1) = governance.userStates(user1);

        uint16 epochDepositedHalf = governance.epoch();

        // =========== epoch 2 (end of cutoff) ==================
        vm.warp(block.timestamp + EPOCH_DURATION - EPOCH_VOTING_CUTOFF);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // user stakes other half
        _stakeLQTY(user1, uint88(lqtyAmount / 2));
        // user votes on bribeInitiative with other half
        _allocateLQTY(user1, lqtyAmount / 2, 0);

        uint16 epochDepositedRest = governance.epoch();
        (, uint32 averageStakingTimestamp2) = governance.userStates(user1);
        assertTrue(
            averageStakingTimestamp1 != averageStakingTimestamp2, "averageStakingTimestamp1 == averageStakingTimestamp2"
        );

        assertEq(epochDepositedHalf, epochDepositedRest, "We are in the same epoch");

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));
        assertEq(4, governance.epoch(), "not in epoch 4");

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, epochToClaimFor, epochDepositedRest, epochDepositedRest);
        assertEq(boldAmount, 1e18, "boldAmount");
        assertEq(bribeTokenAmount, 1e18, "bribeTokenAmount");

        // With non spliting the amount would be 1e18, so this is a bug due to how allocations work
    }

    // checks that user can receive bribes for an epoch in which they were allocated even if they're no longer allocated
    function test_decrement_after_claimBribes() public {
        // =========== epoch 1 ==================
        // user stakes in epoch 1
        _stakeLQTY(user1, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // user votes on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 4
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 5 ==================
        // warp ahead two epochs because bribes can't be claimed in current epoch
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));
        console2.log("current epoch: ", governance.epoch());

        // user should receive bribe from their allocated stake in epoch 2
        uint16 claimEpoch = governance.epoch() - 2; // claim for epoch 3
        uint16 prevAllocationEpoch = governance.epoch() - 2; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);

        // decrease user allocation for the initiative
        _allocateLQTY(user1, 0, 0);

        // check if user can still receive bribes after removing votes
        claimEpoch = governance.epoch() - 1; // claim for epoch 4
        prevAllocationEpoch = governance.epoch() - 2; // epoch 3
        (boldAmount, bribeTokenAmount) = _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
    }

    function test_lqty_immediately_allocated() public {
        // =========== epoch 1 ==================
        // user stakes in epoch 1
        _stakeLQTY(user1, 1e18);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // user votes on bribeInitiative
        _allocateLQTY(user1, 1e18, 0);
        (uint88 lqtyAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(lqtyAllocated, 1e18, "lqty doesn't immediately get allocated");
    }

    // forge test --match-test test_rationalFlow -vvvv
    function test_rationalFlow() public {
        vm.warp(block.timestamp + (EPOCH_DURATION)); // Initiative not active

        // We are now at epoch

        // Deposit
        _stakeLQTY(user1, 1e18);

        // Deposit Bribe for now
        _allocateLQTY(user1, 5e17, 0);
        /// @audit Allocate b4 or after bribe should be irrelevant

        /// @audit WTF
        _depositBribe(1e18, 1e18, governance.epoch());
        /// @audit IMO this should also work

        _allocateLQTY(user1, 5e17, 0);

        /// @audit Allocate b4 or after bribe should be irrelevant

        // deposit bribe for Epoch + 2
        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 5e17, "total allocation");
        assertEq(userLQTYAllocated, 5e17, "user allocation");

        vm.warp(block.timestamp + (EPOCH_DURATION));
        // We are now at epoch + 1 // Should be able to claim epoch - 1

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, governance.epoch() - 1, governance.epoch() - 1, governance.epoch() - 1);
        assertEq(boldAmount, 1e18, "bold amount");
        assertEq(bribeTokenAmount, 1e18, "bribe amount");

        // And they cannot claim the one that is being added currently
        _claimBribe(user1, governance.epoch(), governance.epoch() - 1, governance.epoch() - 1, true);

        // decrease user allocation for the initiative
        _allocateLQTY(user1, 0, 0);

        (userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        (totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(userLQTYAllocated, 0, "total allocation");
        assertEq(totalLQTYAllocated, 0, "user allocation");
    }

    /**
     * Revert Cases
     */
    function test_depositBribe_epoch_too_early_reverts() public {
        vm.startPrank(lusdHolder);

        lqty.approve(address(bribeInitiative), 1e18);
        lusd.approve(address(bribeInitiative), 1e18);

        vm.expectRevert("BribeInitiative: only-future-epochs");
        bribeInitiative.depositBribe(1e18, 1e18, uint16(0));

        vm.stopPrank();
    }

    function test_claimBribes_before_deposit_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        vm.startPrank(user1);

        // should be zero since user1 was not deposited at that time
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 1;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 1;
        vm.expectRevert();
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        assertEq(boldAmount, 0);
        assertEq(bribeTokenAmount, 0);

        vm.stopPrank();
    }

    function test_claimBribes_current_epoch_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        vm.startPrank(user1);

        // should be zero since user1 was not deposited at that time
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch();
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 1;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 1;
        vm.expectRevert("BribeInitiative: cannot-claim-for-current-epoch");
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        assertEq(boldAmount, 0);
        assertEq(bribeTokenAmount, 0);

        vm.stopPrank();
    }

    function test_claimBribes_same_epoch_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        // user should receive bribe from their allocated stake
        (uint256 boldAmount1, uint256 bribeTokenAmount1) =
            _claimBribe(user1, governance.epoch() - 1, governance.epoch() - 2, governance.epoch() - 2);
        assertEq(boldAmount1, 1e18);
        assertEq(bribeTokenAmount1, 1e18);

        vm.startPrank(user1);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 2;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 2;
        vm.expectRevert("BribeInitiative: already-claimed");
        (uint256 boldAmount2, uint256 bribeTokenAmount2) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();
    }

    function test_claimBribes_no_bribe_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        vm.startPrank(user1);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 2;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 2;
        vm.expectRevert("BribeInitiative: no-bribe");
        (uint256 boldAmount1, uint256 bribeTokenAmount1) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();

        assertEq(boldAmount1, 0);
        assertEq(bribeTokenAmount1, 0);
    }

    function test_claimBribes_no_allocation_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 0, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 0);
        assertEq(userLQTYAllocated, 0);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        vm.startPrank(user1);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 2;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 2;
        vm.expectRevert("BribeInitiative: invalid-prev-total-lqty-allocation-epoch");
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();

        assertEq(boldAmount, 0);
        assertEq(bribeTokenAmount, 0);
    }

    // requires: no allocation, previousAllocationEpoch > current, next < epoch or next = 0
    function test_claimBribes_invalid_previous_allocation_epoch_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 0, 0);

        (uint88 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 0);
        assertEq(userLQTYAllocated, 0);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        vm.startPrank(user1);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch();
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 2;
        vm.expectRevert("BribeInitiative: invalid-prev-lqty-allocation-epoch");
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();

        assertEq(boldAmount, 0);
        assertEq(bribeTokenAmount, 0);
    }

    /**
     * Helpers
     */
    function _stakeLQTY(address staker, uint88 amount) public {
        vm.startPrank(staker);
        address userProxy = governance.deriveUserProxyAddress(staker);
        lqty.approve(address(userProxy), amount);
        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocateLQTY(address staker, int88 deltaVoteLQTYAmt, int88 deltaVetoLQTYAmt) public {
        vm.startPrank(staker);
        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);

        // voting in favor of the  initiative with half of user1's stake
        int88[] memory deltaVoteLQTY = new int88[](1);
        deltaVoteLQTY[0] = deltaVoteLQTYAmt;

        int88[] memory deltaVetoLQTY = new int88[](1);
        deltaVetoLQTY[0] = deltaVetoLQTYAmt;

        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.stopPrank();
    }

    function _allocate(address staker, address initiative, int88 votes, int88 vetos) internal {
        vm.startPrank(staker);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = votes;
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = vetos;

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function _depositBribe(uint128 boldAmount, uint128 bribeAmount, uint16 epoch) public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), boldAmount);
        lusd.approve(address(bribeInitiative), bribeAmount);
        bribeInitiative.depositBribe(boldAmount, bribeAmount, epoch);
        vm.stopPrank();
    }

    function _depositBribe(address initiative, uint128 boldAmount, uint128 bribeAmount, uint16 epoch) public {
        vm.startPrank(lusdHolder);
        lqty.approve(initiative, boldAmount);
        lusd.approve(initiative, bribeAmount);
        BribeInitiative(initiative).depositBribe(boldAmount, bribeAmount, epoch);
        vm.stopPrank();
    }

    function _claimBribe(
        address claimer,
        uint16 epoch,
        uint16 prevLQTYAllocationEpoch,
        uint16 prevTotalLQTYAllocationEpoch
    ) public returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        return _claimBribe(claimer, epoch, prevLQTYAllocationEpoch, prevTotalLQTYAllocationEpoch, false);
    }

    function _claimBribe(
        address claimer,
        uint16 epoch,
        uint16 prevLQTYAllocationEpoch,
        uint16 prevTotalLQTYAllocationEpoch,
        bool expectRevert
    ) public returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        vm.startPrank(claimer);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = epoch;
        epochs[0].prevLQTYAllocationEpoch = prevLQTYAllocationEpoch;
        epochs[0].prevTotalLQTYAllocationEpoch = prevTotalLQTYAllocationEpoch;
        if (expectRevert) {
            vm.expectRevert();
        }
        (boldAmount, bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();
    }

    function _getUserShareOfAllocationAsPercentage(address user, uint16 epoch)
        internal
        returns (uint256 userShareOfTotalAllocated)
    {
        (uint88 userLqtyAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user, epoch);
        (uint88 totalLqtyAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(epoch);
        userShareOfTotalAllocated = (uint256(userLqtyAllocated) * 10_000) / uint256(totalLqtyAllocated);
    }

    function _getBribesAsPercentageOfTotal(uint16 epoch, uint256 userBoldAmount, uint256 userBribeTokenAmount)
        internal
        returns (uint256 userShareOfTotalBoldForEpoch, uint256 userShareOfTotalBribeForEpoch)
    {
        (uint128 boldAmountForEpoch, uint128 bribeTokenAmountForEpoch) = bribeInitiative.bribeByEpoch(epoch);
        uint256 userShareOfTotalBoldForEpoch = (userBoldAmount * 10_000) / uint256(boldAmountForEpoch);
        uint256 userShareOfTotalBribeForEpoch = (userBribeTokenAmount * 10_000) / uint256(bribeTokenAmountForEpoch);
        return (userShareOfTotalBoldForEpoch, userShareOfTotalBribeForEpoch);
    }
}
