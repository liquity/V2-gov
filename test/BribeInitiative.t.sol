// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {MockStakingV1} from "./mocks/MockStakingV1.sol";

// coverage: forge coverage --mc BribeInitiativeTest --report lcov
contract BribeInitiativeTest is Test {
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    address private constant user1 = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
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
            initialInitiatives
        );

        vm.startPrank(lusdHolder);
        lqty.transfer(user1, 1_000_000e18);
        lusd.transfer(user1, 1_000_000e18);
        lqty.transfer(user2, 1_000_000e18);
        lusd.transfer(user2, 1_000_000e18);
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
        (uint88 totalLQTYAllocated, ) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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
        (uint88 totalLQTYAllocated, ) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        // fast forward to third epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 5e18, 0);

        // total LQTY allocated for this epoch should not change
        (uint88 totalLQTYAllocated2, ) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2, ) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 10e18);
        assertEq(userLQTYAllocated1, 5e18);

    }

    // user1 allocates multiple times in same epoch
    function test_totalLQTYAllocatedByEpoch_vote_same_epoch() public {        
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 5e18);
        assertEq(userLQTYAllocated1, 5e18);

        // vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated2,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated2, 10e18);
        assertEq(userLQTYAllocated2, 10e18);
    }

    function test_allocation_stored_in_list() public {        
        _stakeLQTY(user1, 10e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // user1 allocates in first epoch
        _allocateLQTY(user1, 5e18, 0);
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        // user2 allocates in second epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // user allocations should be disjoint because they're in separate epochs
        _allocateLQTY(user2, 10e18, 0);
        (uint88 totalLQTYAllocated2,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
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
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated1,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);
        assertEq(userLQTYAllocated1, 10e18);

        _allocateLQTY(user2, 10e18, 0);
        (uint88 totalLQTYAllocated2,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated2,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user2, governance.epoch());
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
        (uint88 totalLQTYAllocated1,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(totalLQTYAllocated1, 10e18);

        // warp to the end of the epoch
        vm.warp(block.timestamp + (EPOCH_VOTING_CUTOFF - 1)); 

        (uint88 totalLQTYAllocated2,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
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

    function test_claimBribes() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) = _claimBribe(user1, governance.epoch() - 1, governance.epoch() - 2, governance.epoch() - 2);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
    }

    function test_decrement_after_claimBribes() public {
        _stakeLQTY(user1, 1e18);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _depositBribe(1e18, 1e18, governance.epoch() + 1);

        vm.warp(block.timestamp + EPOCH_DURATION);

        _allocateLQTY(user1, 1e18, 0);

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        // user should receive bribe from their allocated stake
        (uint256 boldAmount, uint256 bribeTokenAmount) = _claimBribe(user1, governance.epoch() - 1, governance.epoch() - 2, governance.epoch() - 2);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);

        // decrease user allocation for the initiative
        _allocateLQTY(user1, -1e18, 0);

        (userLQTYAllocated,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        (totalLQTYAllocated,) = bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        assertEq(userLQTYAllocated, 0);
        assertEq(totalLQTYAllocated, 0);
    }

    /** 
        Revert Cases
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
        assertEq(totalLQTYAllocated, 1e18);
        assertEq(userLQTYAllocated, 1e18);

        // deposit bribe
        _depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + (EPOCH_DURATION * 2));

        // user should receive bribe from their allocated stake
        (uint256 boldAmount1, uint256 bribeTokenAmount1) = _claimBribe(user1, governance.epoch() - 1, governance.epoch() - 2, governance.epoch() - 2);
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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

        (uint88 totalLQTYAllocated,) =
            bribeInitiative.totalLQTYAllocatedByEpoch(governance.epoch());
        (uint88 userLQTYAllocated,) =
            bribeInitiative.lqtyAllocatedByUserAtEpoch(user1, governance.epoch());
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
        Helpers
    */
    function _stakeLQTY(address staker, uint88 amount) public {
        vm.startPrank(staker);
        address userProxy = governance.deriveUserProxyAddress(staker);
        lqty.approve(address(userProxy), amount);
        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocateLQTY(address staker, int176 deltaVoteLQTYAmt, int176 deltaVetoLQTYAmt) public {
        vm.startPrank(staker);
        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);

        // voting in favor of the  initiative with half of user1's stake
        int176[] memory deltaVoteLQTY = new int176[](1);
        deltaVoteLQTY[0] = deltaVoteLQTYAmt;

        int176[] memory deltaVetoLQTY = new int176[](1);
        deltaVetoLQTY[0] = deltaVetoLQTYAmt;

        governance.allocateLQTY(initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.stopPrank();
    }

    function _depositBribe(uint128 boldAmount, uint128 bribeAmount, uint16 epoch) public {
        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), boldAmount);
        lusd.approve(address(bribeInitiative), bribeAmount);
        bribeInitiative.depositBribe(1e18, 1e18, epoch);
        vm.stopPrank();
    }

    function _claimBribe(address claimer, uint16 epoch, uint16 prevLQTYAllocationEpoch, uint16 prevTotalLQTYAllocationEpoch) public returns (uint256 boldAmount, uint256 bribeTokenAmount){
        vm.startPrank(claimer);
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = epoch;
        epochs[0].prevLQTYAllocationEpoch = prevLQTYAllocationEpoch;
        epochs[0].prevTotalLQTYAllocationEpoch = prevTotalLQTYAllocationEpoch;
        (boldAmount, bribeTokenAmount) = bribeInitiative.claimBribes(epochs);
        vm.stopPrank();
    }
}
