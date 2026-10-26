// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {CurveV2GaugeRewardsNoBribesInitiative} from "../src/CurveV2GaugeRewardsNoBribesInitiative.sol";
import {Governance} from "../src/Governance.sol";

contract ForkedCurveV2GaugeRewardsNoBribesInitiativeTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    IERC20 private constant bold = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
    IERC20 private constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    ICurveStableswapNG private constant curvePool = ICurveStableswapNG(0xEFc6516323FbD28e80B85A497B65A86243a54B3E);
    ILiquidityGauge private constant gauge = ILiquidityGauge(0x07a01471fA544D9C6531B631E6A96A79a9AD05E9);
    address private constant boldHolder = address(0xabF2A7d999d7eBF2A0e29F267E6Bc93198818a96);
    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(address(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf));

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;
    uint256 private constant DEPOSIT_THRESHOLD = EPOCH_DURATION * 1000;

    Governance private governance;
    address[] private initialInitiatives;
    CurveV2GaugeRewardsNoBribesInitiative private curveV2GaugeRewardsNoBribes;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 26260000);

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            epochStart: uint32(block.timestamp),
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance(
            address(lqty), address(lusd), stakingV1, address(bold), config, address(this), initialInitiatives
        );

        curveV2GaugeRewardsNoBribes = new CurveV2GaugeRewardsNoBribesInitiative(
            // address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(governance),
            address(bold),
            address(gauge),
            EPOCH_DURATION
        );

        initialInitiatives.push(address(curveV2GaugeRewardsNoBribes));
        governance.registerInitialInitiatives(initialInitiatives);

        vm.prank(curveFactory.admin());
        gauge.set_reward_distributor(address(bold), address(curveV2GaugeRewardsNoBribes));
    }

    function test_claimAndDepositIntoGaugeFuzz(uint128 amt) public {
        deal(address(bold), address(governance), amt);
        vm.assume(amt > DEPOSIT_THRESHOLD);

        // Pretend a Proposal has passed
        vm.prank(address(governance));
        bold.transfer(address(curveV2GaugeRewardsNoBribes), amt);

        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), amt);
        uint256 gaugeBalanceBefore = bold.balanceOf(address(gauge));

        curveV2GaugeRewardsNoBribes.claimForInitiative();
        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), 0);
        assertEq(bold.balanceOf(address(gauge)) - gaugeBalanceBefore, amt);
    }

    function test_claimAndDepositIntoGaugeGrief() public {
        uint256 amt = DEPOSIT_THRESHOLD - 1;
        deal(address(bold), address(governance), amt);

        // Pretend a Proposal has passed
        vm.prank(address(governance));
        bold.transfer(address(curveV2GaugeRewardsNoBribes), amt);

        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), amt);
        curveV2GaugeRewardsNoBribes.claimForInitiative();
        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), amt);
    }

    /// @dev Fuzz test that shows that given a total = amt + dust, the dust is not lost
    function test_noDustGriefFuzz(uint128 amt, uint128 dust) public {
        uint256 total = uint256(amt) + uint256(dust);
        deal(address(bold), address(governance), total);

        // Pretend a Proposal has passed
        // Dust amount
        vm.prank(address(governance));
        bold.transfer(address(curveV2GaugeRewardsNoBribes), amt);
        // Rest
        vm.prank(address(governance));
        bold.transfer(address(curveV2GaugeRewardsNoBribes), dust);

        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), total);
        uint256 gaugeBalanceBefore = bold.balanceOf(address(gauge));

        curveV2GaugeRewardsNoBribes.claimForInitiative();

        if (total >= DEPOSIT_THRESHOLD) {
            assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), 0);
            assertApproxEqAbs(bold.balanceOf(address(gauge)) - gaugeBalanceBefore, total, 1);
        } else {
            assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), total);
            // Next week it can be claimed
            vm.warp(block.timestamp + 1 weeks);
            uint256 remainderAmount = DEPOSIT_THRESHOLD - total;

            deal(address(bold), address(this), remainderAmount);
            bold.transfer(address(curveV2GaugeRewardsNoBribes), remainderAmount);
            curveV2GaugeRewardsNoBribes.claimForInitiative();

            assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), 0);
            assertApproxEqAbs(bold.balanceOf(address(gauge)) - gaugeBalanceBefore, total + remainderAmount, 1);
        }
    }

    function test_claimFrontrun(uint128 amt) public {
        deal(address(bold), address(governance), amt);
        vm.assume(amt > DEPOSIT_THRESHOLD);

        // Pretend a Proposal has passed
        vm.prank(address(governance));
        bold.transfer(address(curveV2GaugeRewardsNoBribes), amt);

        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), amt);
        uint256 gaugeBalanceBefore = bold.balanceOf(address(gauge));

        // Someone frontruns the call to governance
        governance.claimForInitiative(address(this));

        // Now we use the wrapper
        curveV2GaugeRewardsNoBribes.claimForInitiative();
        assertEq(bold.balanceOf(address(curveV2GaugeRewardsNoBribes)), 0);
        assertEq(bold.balanceOf(address(gauge)) - gaugeBalanceBefore, amt);
    }
}
