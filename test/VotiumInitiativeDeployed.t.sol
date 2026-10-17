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

contract ForkedVotiumInitiativeDeployedTest is Test {
    IERC20 private constant lqty = IERC20(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D);
    IERC20 private constant bold = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
    address private constant stakingV1 = 0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d;
    //address private constant boldHolder = 0xabF2A7d999d7eBF2A0e29F267E6Bc93198818a96;
    address constant GOVERNANCE_WHALE = 0xF30da4E4e7e20Dbf5fBE9adCD8699075D62C60A4;
    address public constant votium = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    //address private constant gauge = 0x07a01471fA544D9C6531B631E6A96A79a9AD05E9;
    Governance private constant governance = Governance(0x807DEf5E7d057DF05C796F4bc75C3Fe82Bd6EeE1);
    VotiumInitiative private constant votiumInitiative = VotiumInitiative(0x69eFEc83296c711db4A403B1Ee281E87f99590d6);

    uint32 private constant EPOCH_DURATION = 604800;
    uint256 private constant DEPOSIT_THRESHOLD = EPOCH_DURATION * 1000;
    uint256 private constant VOTIUM_FEE = 0.02 ether; // 2%
    uint256 private constant DECIMAL_PRECISION = 1e18;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 25336275);

        uint256 REGISTRATION_FEE = governance.REGISTRATION_FEE();

        deal(address(bold), GOVERNANCE_WHALE, REGISTRATION_FEE);
        vm.startPrank(GOVERNANCE_WHALE);
        bold.approve(address(governance), REGISTRATION_FEE);
        governance.registerInitiative(address(votiumInitiative));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
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

    /// @dev Fuzz test that shows that given a total = amt + dust, the dust is lost permanently
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

        assertEq(bold.balanceOf(address(votiumInitiative)), votiumInitiative.remainder() + dust);
    }

    function getNetAmount(uint256 _amount) internal pure returns (uint256) {
        return (DECIMAL_PRECISION - VOTIUM_FEE) * _amount / DECIMAL_PRECISION;
    }
}
