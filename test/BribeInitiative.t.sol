// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";

import {MockStakingV1} from "./mocks/MockStakingV1.sol";

contract BribeInitiativeTest is Test {
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);
    address private constant initiative2 = address(0x2);
    address private constant initiative3 = address(0x3);

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    BribeInitiative private bribeInitiative;

    function setUp() public {
        lqty = deployMockERC20("Liquity", "LQTY", 18);
        lusd = deployMockERC20("Liquity USD", "LUSD", 18);

        vm.store(address(lqty), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));
        vm.store(address(lusd), keccak256(abi.encode(address(lusdHolder), 4)), bytes32(abi.encode(10000e18)));

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
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
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
        lqty.transfer(user, 1e18);
        lusd.transfer(user, 1e18);
        vm.stopPrank();
    }

    function test_claimBribes() public {
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();
        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1e18);
        lusd.approve(address(bribeInitiative), 1e18);
        bribeInitiative.depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.stopPrank();

        vm.startPrank(user);

        vm.warp(block.timestamp + 365 days);

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);
        int176[] memory deltaVoteLQTY = new int176[](1);
        deltaVoteLQTY[0] = 1e18;
        int176[] memory deltaVetoLQTY = new int176[](1);
        governance.allocateLQTY(initiatives, deltaVoteLQTY, deltaVetoLQTY);

        // should be zero since user was not deposited at that time
        BribeInitiative.ClaimData[] memory epochs = new BribeInitiative.ClaimData[](1);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 1;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 1;
        vm.expectRevert();
        (uint256 boldAmount, uint256 bribeTokenAmount) = bribeInitiative.claimBribes(user, epochs);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lqty.approve(address(bribeInitiative), 1e18);
        lusd.approve(address(bribeInitiative), 1e18);
        bribeInitiative.depositBribe(1e18, 1e18, governance.epoch() + 1);
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.stopPrank();

        vm.startPrank(user);
        epochs[0].epoch = governance.epoch() - 1;
        epochs[0].prevLQTYAllocationEpoch = governance.epoch() - 2;
        epochs[0].prevTotalLQTYAllocationEpoch = governance.epoch() - 2;
        (boldAmount, bribeTokenAmount) = bribeInitiative.claimBribes(user, epochs);
        assertEq(boldAmount, 1e18);
        assertEq(bribeTokenAmount, 1e18);
        vm.stopPrank();
    }
}
