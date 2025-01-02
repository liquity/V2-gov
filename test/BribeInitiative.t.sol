// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "../src/interfaces/IBribeInitiative.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";

contract BribeInitiativeTest is Test, MockStakingV1Deployer {
    using Strings for uint256;

    MockERC20Tester private lqty;
    MockERC20Tester private lusd;
    MockStakingV1 private stakingV1;
    address private constant user1 = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address private user3 = makeAddr("user3");
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint256 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 7 days; // 7 days
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    BribeInitiative private bribeInitiative;

    function setUp() public {
        (stakingV1, lqty, lusd) = deployMockStakingV1();

        lqty.mint(lusdHolder, 10_000_000e18);
        lusd.mint(lusdHolder, 10_000_000e18);

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            epochStart: uint256(block.timestamp),
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance(
            address(lqty), address(lusd), address(stakingV1), address(lusd), config, address(this), new address[](0)
        );

        bribeInitiative = new BribeInitiative(address(governance), address(lusd), address(lqty));
        initialInitiatives.push(address(bribeInitiative));
        governance.registerInitialInitiatives(initialInitiatives);

        vm.startPrank(lusdHolder);
        lqty.transfer(user1, 1_000_000e18);
        lusd.transfer(user1, 1_000_000e18);
        lqty.transfer(user2, 1_000_000e18);
        lusd.transfer(user2, 1_000_000e18);
        lqty.transfer(user3, 1_000_000e18);
        lusd.transfer(user3, 1_000_000e18);
        vm.stopPrank();
    }

    function test_bribeToken_cannot_be_BOLD() external {
        vm.expectRevert("BribeInitiative: bribe-token-cannot-be-bold");
        new BribeInitiative({_governance: address(governance), _bold: address(lusd), _bribeToken: address(lusd)});
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
        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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
        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        // fast forward to third epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 5e18, 0);

        // total LQTY allocated for this epoch should not change
        (uint256 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 5e18);
        assertEq(userLQTYAllocated1, 5e18);
    }

    // user1 allocates multiple times in same epoch
    function test_totalLQTYAllocatedByEpoch_vote_same_epoch() public {
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        _allocateLQTY(user1, 5e18, 0);
        (uint256 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 5e18);
        assertEq(userLQTYAllocated2, 5e18);
    }

    function test_allocation_stored_in_list() public {
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        console2.log("current governance epoch: ", governance.epoch());
        // user's linked-list should be updated to have a value for the current epoch
        (uint256 allocatedAtEpoch,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        console2.log("allocatedAtEpoch: ", allocatedAtEpoch);
    }

    // test total allocation by multiple users in multiple epochs
    function test_totalLQTYAllocatedByEpoch_vote_multiple_epochs() public {
        _stakeLQTY(user1, 10e18);
        _stakeLQTY(user2, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 10e18, 0);
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        // user2 allocates in second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // user allocations should be disjoint because they're in separate epochs
        _allocateLQTY(user2, 10e18, 0);
        (uint256 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
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
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated1,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        _allocateLQTY(user2, 10e18, 0);
        (uint256 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated2,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
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
        (uint256 totalLQTYAllocated1,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);

        // warp to the end of the epoch
        vm.warp(block.timestamp + (EPOCH_VOTING_CUTOFF - 1));

        (uint256 totalLQTYAllocated2,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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
        uint256 depositedBribe = governance.epoch() + 1;

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
        _resetAllocation(user2);

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION); // Needs to cause rounding error
        assertEq(3, governance.epoch(), "not in epoch 2");

        // user votes on bribeInitiative

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) = _claimBribe(user1, 2, 2, 2);
        assertEq(boldAmount, 1e18, "BOLD amount mismatch");
        assertEq(bribeTokenAmount, 1e18, "Bribe token amount mismatch");
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
        (uint256 boldAmountFromStorage, uint256 bribeTokenAmountFromStorage,) =
            IBribeInitiative(bribeInitiative).bribeByEpoch(governance.epoch() - 2);
        assertEq(boldAmountFromStorage, 1e18, "boldAmountFromStorage != 1e18");
        assertEq(bribeTokenAmountFromStorage, 1e18, "bribeTokenAmountFromStorage != 1e18");

        // check amount of bribes in epoch 4
        (boldAmountFromStorage, bribeTokenAmountFromStorage,) =
            IBribeInitiative(bribeInitiative).bribeByEpoch(governance.epoch() - 1);
        assertEq(boldAmountFromStorage, 1e18, "boldAmountFromStorage != 1e18");
        assertEq(bribeTokenAmountFromStorage, 1e18, "bribeTokenAmountFromStorage != 1e18");

        // user should receive bribe from their allocated stake for each epoch

        // user claims for epoch 3
        uint256 claimEpoch = governance.epoch() - 2; // claim for epoch 3
        uint256 prevAllocationEpoch = governance.epoch() - 2; // epoch 3
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
        uint256 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint256 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);

        assertEq(boldAmount, 0.5e18, "wrong BOLD amount");
        assertEq(bribeTokenAmount, 0.5e18, "wrong bribe token amount");
    }

    function test_claimedBribes_fraction_fuzz(
        uint256[3] memory userStakeAmount,
        uint256 boldAmount,
        uint256 bribeTokenAmount
    ) public {
        address[3] memory user = [user1, user2, user3];
        assertEq(user.length, userStakeAmount.length, "user.length != userStakeAmount.length");

        // =========== epoch 1 ==================
        boldAmount = bound(boldAmount, 1, lusd.balanceOf(lusdHolder));
        bribeTokenAmount = bound(bribeTokenAmount, 1, lqty.balanceOf(lusdHolder));

        // all users stake in epoch 1
        uint256 totalStakeAmount;
        for (uint256 i = 0; i < user.length; ++i) {
            totalStakeAmount += userStakeAmount[i] = bound(userStakeAmount[i], 1, lqty.balanceOf(user[i]));
            _stakeLQTY(user[i], userStakeAmount[i]);
        }

        // =========== epoch 2 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(2, governance.epoch(), "not in epoch 2");

        // lusdHolder deposits lqty and lusd bribes claimable in epoch 3
        _depositBribe(boldAmount, bribeTokenAmount, governance.epoch() + 1);

        // =========== epoch 3 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in epoch 3");

        // users all vote on bribeInitiative
        for (uint256 i = 0; i < user.length; ++i) {
            _allocateLQTY(user[i], int256(userStakeAmount[i]), 0);
        }

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(4, governance.epoch(), "not in epoch 4");

        // all users claim bribes for epoch 3
        uint256 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint256 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        uint256 totalClaimedBoldAmount;
        uint256 totalClaimedBribeTokenAmount;

        for (uint256 i = 0; i < user.length; ++i) {
            (uint256 claimedBoldAmount, uint256 claimedBribeTokenAmount) =
                _claimBribe(user[i], claimEpoch, prevAllocationEpoch, prevAllocationEpoch);

            assertApproxEqAbs(
                claimedBoldAmount,
                boldAmount * userStakeAmount[i] / totalStakeAmount,
                // we expect `claimedBoldAmount` to be within `idealAmount +/- 1`
                // where `idealAmount = boldAmount * userStakeAmount[i] / totalStakeAmount`,
                // however our calculation of `idealAmount` itself has a rounding error of `(-1, 0]`,
                // so the total difference can add up to 2
                2,
                string.concat("wrong BOLD amount for user[", i.toString(), "]")
            );

            totalClaimedBoldAmount += claimedBoldAmount;
            totalClaimedBribeTokenAmount += claimedBribeTokenAmount;
        }

        // total
        assertEq(totalClaimedBoldAmount, boldAmount, "there should be no BOLD dust left");
        assertEq(totalClaimedBribeTokenAmount, bribeTokenAmount, "there should be no bribe token dust left");
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
        uint256 claimEpoch = governance.epoch() - 1; // claim for epoch 3
        uint256 prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18, "voter doesn't receive full bold bribe amount");
        assertEq(bribeTokenAmount, 1e18, "voter doesn't receive full bribe amount");

        // user2 should receive no bribes if they try to claim
        claimEpoch = governance.epoch() - 1; // claim for epoch 3
        prevAllocationEpoch = governance.epoch() - 1; // epoch 3
        (boldAmount, bribeTokenAmount) = _claimBribe(user2, claimEpoch, prevAllocationEpoch, prevAllocationEpoch, true);
        assertEq(boldAmount, 0, "vetoer receives bold bribe amount");
        assertEq(bribeTokenAmount, 0, "vetoer receives bribe amount");
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
        uint256 claimEpoch = governance.epoch() - 2; // claim for epoch 3
        uint256 prevAllocationEpoch = governance.epoch() - 2; // epoch 3
        (uint256 boldAmount, uint256 bribeTokenAmount) =
            _claimBribe(user1, claimEpoch, prevAllocationEpoch, prevAllocationEpoch);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);

        // decrease user allocation for the initiative
        _resetAllocation(user1);

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
        (uint256 lqtyAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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
        _resetAllocation(user1);

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

        vm.expectRevert("BribeInitiative: now-or-future-epochs");
        bribeInitiative.depositBribe(1e18, 1e18, uint256(0));

        vm.stopPrank();
    }

    function test_claimBribes_before_deposit_reverts() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        _tryAllocateNothing(user1);

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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
        vm.expectRevert("BribeInitiative: total-lqty-allocation-zero");
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

        _tryAllocateNothing(user1);

        (uint256 totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint256 userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

    // See https://github.com/liquity/V2-gov/issues/106
    function test_VoterGetsTheirFairShareOfBribes() external {
        uint256 bribeAmount = 10_000 ether;
        uint256 voteAmount = 100_000 ether;
        address otherInitiative = makeAddr("otherInitiative");

        // Fast-forward to enable registration
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);

        vm.startPrank(lusdHolder);
        {
            // Register otherInitiative, so user1 has something else to vote on
            lusd.approve(address(governance), REGISTRATION_FEE);
            governance.registerInitiative(otherInitiative);

            // Deposit some bribes into bribeInitiative in next epoch
            lusd.approve(address(bribeInitiative), bribeAmount);
            lqty.approve(address(bribeInitiative), bribeAmount);
            bribeInitiative.depositBribe(bribeAmount, bribeAmount, governance.epoch() + 1);
        }
        vm.stopPrank();

        // Ensure otherInitiative can be voted on
        vm.warp(block.timestamp + EPOCH_DURATION);

        address[] memory initiativesToReset = new address[](0);
        address[] memory initiatives;
        int256[] memory votes;
        int256[] memory vetos;

        vm.startPrank(user1);
        {
            initiatives = new address[](2);
            votes = new int256[](2);
            vetos = new int256[](2);

            initiatives[0] = otherInitiative;
            initiatives[1] = address(bribeInitiative);
            votes[0] = int256(voteAmount);
            votes[1] = int256(voteAmount);

            lqty.approve(governance.deriveUserProxyAddress(user1), 2 * voteAmount);
            governance.depositLQTY(2 * voteAmount);
            governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
        }
        vm.stopPrank();

        vm.startPrank(user2);
        {
            initiatives = new address[](1);
            votes = new int256[](1);
            vetos = new int256[](1);

            initiatives[0] = address(bribeInitiative);
            votes[0] = int256(voteAmount);

            lqty.approve(governance.deriveUserProxyAddress(user2), voteAmount);
            governance.depositLQTY(voteAmount);
            governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
        }
        vm.stopPrank();

        // Fast-forward to next epoch, so previous epoch's bribes can be claimed
        vm.warp(block.timestamp + EPOCH_DURATION);

        IBribeInitiative.ClaimData[] memory claimData = new IBribeInitiative.ClaimData[](1);
        claimData[0].epoch = governance.epoch() - 1;
        claimData[0].prevLQTYAllocationEpoch = governance.epoch() - 1;
        claimData[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 1;

        vm.prank(user1);
        (uint256 lusdBribe, uint256 lqtyBribe) = bribeInitiative.claimBribes(claimData);
        assertEqDecimal(lusdBribe, bribeAmount / 2, 18, "user1 didn't get their fair share of LUSD");
        assertEqDecimal(lqtyBribe, bribeAmount / 2, 18, "user1 didn't get their fair share of LQTY");
    }

    /**
     * Helpers
     */
    function _stakeLQTY(address staker, uint256 amount) internal {
        vm.startPrank(staker);
        address userProxy = governance.deriveUserProxyAddress(staker);
        lqty.approve(address(userProxy), amount);
        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocateLQTY(address staker, int256 absoluteVoteLQTYAmt, int256 absoluteVetoLQTYAmt) internal {
        vm.startPrank(staker);
        address[] memory initiativesToReset;
        (uint256 currentVote,, uint256 currentVeto,,) =
            governance.lqtyAllocatedByUserToInitiative(staker, address(bribeInitiative));
        if (currentVote != 0 || currentVeto != 0) {
            initiativesToReset = new address[](1);
            initiativesToReset[0] = address(bribeInitiative);
        }

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);

        int256[] memory absoluteVoteLQTY = new int256[](1);
        absoluteVoteLQTY[0] = absoluteVoteLQTYAmt;

        int256[] memory absoluteVetoLQTY = new int256[](1);
        absoluteVetoLQTY[0] = absoluteVetoLQTYAmt;

        governance.allocateLQTY(initiativesToReset, initiatives, absoluteVoteLQTY, absoluteVetoLQTY);
        vm.stopPrank();
    }

    function _allocate(address staker, address initiative, int256 votes, int256 vetos) internal {
        vm.startPrank(staker);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory absoluteLQTYVotes = new int256[](1);
        absoluteLQTYVotes[0] = votes;
        int256[] memory absoluteLQTYVetos = new int256[](1);
        absoluteLQTYVetos[0] = vetos;

        governance.allocateLQTY(initiatives, initiatives, absoluteLQTYVotes, absoluteLQTYVetos);

        vm.stopPrank();
    }

    function _tryAllocateNothing(address staker) internal {
        vm.startPrank(staker);
        address[] memory initiativesToReset;

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);

        int256[] memory absoluteVoteLQTY = new int256[](1);
        int256[] memory absoluteVetoLQTY = new int256[](1);

        vm.expectRevert("Governance: voting nothing");
        governance.allocateLQTY(initiativesToReset, initiatives, absoluteVoteLQTY, absoluteVetoLQTY);
        vm.stopPrank();
    }

    function _resetAllocation(address staker) internal {
        vm.startPrank(staker);
        address[] memory initiativesToReset = new address[](1);
        initiativesToReset[0] = address(bribeInitiative);

        governance.resetAllocations(initiativesToReset, true);
        vm.stopPrank();
    }

    function _depositBribe(uint256 boldAmount, uint256 bribeAmount, uint256 epoch) public {
        vm.startPrank(lusdHolder);
        lusd.approve(address(bribeInitiative), boldAmount);
        lqty.approve(address(bribeInitiative), bribeAmount);
        bribeInitiative.depositBribe(boldAmount, bribeAmount, epoch);
        vm.stopPrank();
    }

    function _depositBribe(address _initiative, uint256 boldAmount, uint256 bribeAmount, uint256 epoch) public {
        vm.startPrank(lusdHolder);
        lusd.approve(_initiative, boldAmount);
        lqty.approve(_initiative, bribeAmount);
        BribeInitiative(_initiative).depositBribe(boldAmount, bribeAmount, epoch);
        vm.stopPrank();
    }

    function _claimBribe(
        address claimer,
        uint256 epoch,
        uint256 prevLQTYAllocationEpoch,
        uint256 prevTotalLQTYAllocationEpoch
    ) public returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        return _claimBribe(claimer, epoch, prevLQTYAllocationEpoch, prevTotalLQTYAllocationEpoch, false);
    }

    function _claimBribe(
        address claimer,
        uint256 epoch,
        uint256 prevLQTYAllocationEpoch,
        uint256 prevTotalLQTYAllocationEpoch,
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
}
