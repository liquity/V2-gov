// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {MockStakingV1} from "./MockStakingV1.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {Governance} from "../src/Governance.sol";
import {BaseInitiative} from "../src/BaseInitiative.sol";

interface ILQTY {
    function domainSeparator() external view returns (bytes32);
}

contract BaseInitiativeTest is Test {
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);
    address private constant initiative2 = address(0x2);
    address private constant initiative3 = address(0x3);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;
    uint256 private constant ALLOCATION_DELAY = 1;

    Governance private governance;
    address[] private initialInitiatives;

    BaseInitiative private baseInitiative;

    // BribeProxy private bribeProxy;

    function setUp() public {
        lqty = deployMockERC20("Liquity", "LQTY", 18);
        lusd = deployMockERC20("Liquity USD", "LUSD", 18);

        vm.store(address(lqty), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));
        vm.store(address(lusd), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));

        stakingV1 = address(new MockStakingV1(address(lqty)));

        baseInitiative = new BaseInitiative(
            address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(lusd),
            address(lqty)
        );

        initialInitiatives.push(address(baseInitiative));

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF,
                allocationDelay: ALLOCATION_DELAY
            }),
            initialInitiatives
        );

        vm.startPrank(lusdHolder);
        lqty.transfer(user, 1e18);
        vm.stopPrank();
    }

    function test_claimBribes() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();
        lqty.approve(address(userProxy), 1e18);
        assertEq(governance.depositLQTY(1e18), 1e18);

        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(lusdHolder);

        lqty.approve(address(baseInitiative), 1e18);
        baseInitiative.depositBribe(1e18, governance.epoch());

        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(baseInitiative);
        int256[] memory deltaShares = new int256[](1);
        int256[] memory deltaVetoShares = new int256[](1);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + 365 days);

        initiatives = new address[](1);
        initiatives[0] = address(baseInitiative);
        deltaShares = new int256[](1);
        deltaShares[0] = 1e18;
        deltaVetoShares = new int256[](1);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.stopPrank();
    }
}
