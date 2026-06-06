// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {IVotium} from "../src/interfaces/IVotium.sol";

import {VotiumInitiative} from "../src/VotiumInitiative.sol";
import {Governance} from "../src/Governance.sol";

contract ForkedVotiumInitiativeTest is Test {
    IERC20 private constant lqty = IERC20(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D);
    IERC20 private constant bold = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
    IERC20 private constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant stakingV1 = 0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d;
    address private constant user = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    //address private constant boldHolder = 0xabF2A7d999d7eBF2A0e29F267E6Bc93198818a96;
    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf);
    ICurveStableswapNG private constant curvePool = ICurveStableswapNG(0xEFc6516323FbD28e80B85A497B65A86243a54B3E);
    address public constant votium = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    address private constant gauge = 0x07a01471fA544D9C6531B631E6A96A79a9AD05E9;

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
    uint256 private constant VOTIUM_FEE = 0.02 ether; // 2%
    uint256 private constant DECIMAL_PRECISION = 1e18;

    Governance private governance;
    address[] private initialInitiatives;
    VotiumInitiative private votiumInitiative;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 25260251);

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
            address(lqty), address(bold), stakingV1, address(bold), config, address(this), initialInitiatives
        );

        votiumInitiative = new VotiumInitiative(
            // address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(governance),
            address(bold),
            address(lqty),
            address(votium),
            gauge,
            EPOCH_DURATION
        );

        initialInitiatives.push(address(votiumInitiative));
        governance.registerInitialInitiatives(initialInitiatives);
    }

    function test_claimAndDepositIntoGaugeFuzz(uint128 amt) public {
        deal(address(bold), address(governance), amt);
        vm.assume(amt > DEPOSIT_THRESHOLD);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        bold.transfer(address(votiumInitiative), amt);

        assertEq(bold.balanceOf(address(votiumInitiative)), amt);
        votiumInitiative.onClaimForInitiative(0, amt);
        assertEq(bold.balanceOf(address(votiumInitiative)), 0);
        assertApproxEqAbs(bold.balanceOf(address(votium)), getNetAmount(amt), 1);
    }

    /// @dev If the amount rounds down below 1 per second it reverts
    function test_claimAndDepositIntoGaugeGrief() public {
        uint256 amt = DEPOSIT_THRESHOLD - 1;
        deal(address(bold), address(governance), amt);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        bold.transfer(address(votiumInitiative), amt);

        assertEq(bold.balanceOf(address(votiumInitiative)), amt);
        votiumInitiative.onClaimForInitiative(0, amt);
        assertEq(bold.balanceOf(address(votiumInitiative)), amt);
        assertEq(bold.balanceOf(address(votium)), 0);
    }

    /// @dev Fuzz test that shows that given a total = amt + dust, the dust is not lost
    function test_noDustGriefFuzz(uint128 amt, uint128 dust) public {
        uint256 total = uint256(amt) + uint256(dust);
        deal(address(bold), address(governance), total);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        // Dust amount
        bold.transfer(address(votiumInitiative), amt);
        // Rest
        bold.transfer(address(votiumInitiative), dust);

        assertEq(bold.balanceOf(address(votiumInitiative)), total);
        votiumInitiative.onClaimForInitiative(0, amt);
        if (total >= DEPOSIT_THRESHOLD) {
            assertEq(bold.balanceOf(address(votiumInitiative)), 0);
            assertApproxEqAbs(bold.balanceOf(address(votium)), getNetAmount(total), 1);
        } else {
            assertEq(bold.balanceOf(address(votiumInitiative)), total);
            // Next week it can be claimed
            vm.warp(block.timestamp + 1 weeks);
            uint256 remainderAmount = DEPOSIT_THRESHOLD - total;
            deal(address(bold), address(governance), remainderAmount);
            bold.transfer(address(votiumInitiative), remainderAmount);
            votiumInitiative.onClaimForInitiative(0, remainderAmount);
            assertEq(bold.balanceOf(address(votiumInitiative)), 0);
            assertApproxEqAbs(bold.balanceOf(address(votium)), getNetAmount(total + remainderAmount), 1);
        }
    }

    function getNetAmount(uint256 _amount) internal returns (uint256) {
        return (DECIMAL_PRECISION - VOTIUM_FEE) * _amount / DECIMAL_PRECISION;
    }
}
