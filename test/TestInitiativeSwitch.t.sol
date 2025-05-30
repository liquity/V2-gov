// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockInitiative} from "./mocks/MockInitiative.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";

import {Governance} from "../src/Governance.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {InitiativeSwitch} from "../src/InitiativeSwitch.sol";

contract TestInitiativeSwitch is MockStakingV1Deployer {
    uint32 constant START_TIME = 1732873631;
    uint32 constant EPOCH_DURATION = 7 days;
    uint32 constant EPOCH_VOTING_CUTOFF = 6 days;

    IGovernance.Configuration config = IGovernance.Configuration({
        registrationFee: 0,
        registrationThresholdFactor: 0,
        unregistrationThresholdFactor: 4 ether,
        unregistrationAfterEpochs: 4,
        votingThresholdFactor: 0,
        minClaim: 0,
        minAccrual: 0,
        epochStart: START_TIME - EPOCH_DURATION,
        epochDuration: EPOCH_DURATION,
        epochVotingCutoff: EPOCH_VOTING_CUTOFF
    });

    MockStakingV1 stakingV1;
    MockERC20Tester lqty;
    MockERC20Tester lusd;
    MockERC20Tester bold;
    MockInitiative public mockInitiative;
    MockInitiative public newMockInitiative;

    Governance governance;
    InitiativeSwitch public initiativeSwitch;

    address[] noInitiatives; // left empty
    address[] initiatives;
    int256[] votes;
    int256[] vetos;
    address owner;
    address voter;

    function setUp() public {
        vm.warp(START_TIME);

        (stakingV1, lqty, lusd) = deployMockStakingV1();

        bold = new MockERC20Tester("BOLD Stablecoin", "BOLD");
        vm.label(address(bold), "BOLD");

        governance = new Governance({
            _lqty: address(lqty),
            _lusd: address(lusd),
            _stakingV1: address(stakingV1),
            _bold: address(bold),
            _config: config,
            _owner: address(this),
            _initiatives: new address[](0)
        });

        mockInitiative = new MockInitiative();
        newMockInitiative = new MockInitiative();
        owner = makeAddr("owner");
        vm.startPrank(owner);
        initiativeSwitch = new InitiativeSwitch(IGovernance(address(governance)), mockInitiative);
        vm.stopPrank();
        initiatives.push(address(initiativeSwitch));
        governance.registerInitialInitiatives(initiatives);

        voter = makeAddr("voter");
        lqty.mint(voter, 1 ether);

        vm.startPrank(voter);
        lqty.approve(governance.deriveUserProxyAddress(voter), type(uint256).max);
        governance.depositLQTY(1 ether);
        vm.stopPrank();

        votes.push();
        vetos.push();
    }

    function testConstructorInitialization() public {
        assertEq(address(initiativeSwitch.governance()), address(governance));
        assertEq(address(initiativeSwitch.bold()), address(bold));
        assertEq(address(initiativeSwitch.target()), address(mockInitiative));
    }

    function testSwitchTarget() public {
        vm.prank(owner);
        initiativeSwitch.switchTarget(newMockInitiative);

        assertEq(address(initiativeSwitch.target()), address(newMockInitiative));
    }

    function testSwitchTargetRevertsIfNotOwner() public {
        vm.expectRevert();
        initiativeSwitch.switchTarget(newMockInitiative);
    }

    function testOnRegisterInitiative() public {
        uint256 epoch = governance.epoch();
        vm.prank(address(governance));
        initiativeSwitch.onRegisterInitiative(epoch);
        // TODO
    }

    function testOnRegisterInitiativeRevertsIfNotGovernance() public {
        vm.expectRevert(bytes("InitiativeSwitch: invalid-sender"));
        initiativeSwitch.onRegisterInitiative(2);
    }

    function testOnUnregisterInitiative() public {
        uint256 epoch = governance.epoch();
        vm.prank(address(governance));
        initiativeSwitch.onUnregisterInitiative(epoch);
        // TODO
    }

    function testOnUnregisterInitiativeRevertsIfNotGovernance() public {
        vm.expectRevert(bytes("InitiativeSwitch: invalid-sender"));
        initiativeSwitch.onUnregisterInitiative(3);
    }

    function testOnAfterAllocateLQTY() public {
        vm.startPrank(voter);
        votes[0] = 123;
        governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(mockInitiative.numOnAfterAllocateLQTYCalls(), 1, "onAfterAllocateLQTY should have been called once");
        (,,, IGovernance.Allocation memory allocation,) = mockInitiative.onAfterAllocateLQTYCalls(0);
        assertEq(allocation.voteLQTY, 123, "wrong voteLQTY 1");

        assertEq(
            newMockInitiative.numOnAfterAllocateLQTYCalls(),
            0,
            "onAfterAllocateLQTY should have not been called on new target"
        );

        // Switch Initiative and allocate
        vm.startPrank(owner);
        initiativeSwitch.switchTarget(newMockInitiative);
        vm.stopPrank();

        vm.startPrank(voter);
        votes[0] = 123;
        governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(mockInitiative.numOnAfterAllocateLQTYCalls(), 1, "onAfterAllocateLQTY should have been called once");
        (,,, allocation,) = mockInitiative.onAfterAllocateLQTYCalls(0);
        assertEq(allocation.voteLQTY, 123, "wrong voteLQTY 1");

        assertEq(newMockInitiative.numOnAfterAllocateLQTYCalls(), 1, "onAfterAllocateLQTY should have been called once");
        (,,, allocation,) = newMockInitiative.onAfterAllocateLQTYCalls(0);
        assertEq(allocation.voteLQTY, 123, "wrong voteLQTY 1");
    }

    function testOnAfterAllocateLQTYRevertsIfNotGovernance() public {
        uint256 epoch = 4;
        address user = address(1);
        IGovernance.UserState memory userState = IGovernance.UserState({
            unallocatedLQTY: 1e18,
            unallocatedOffset: 1,
            allocatedLQTY: 2e18,
            allocatedOffset: 2
        });
        IGovernance.Allocation memory allocation =
            IGovernance.Allocation({voteLQTY: 1e18, voteOffset: 2e18, vetoLQTY: 0, vetoOffset: 0, atEpoch: 1});
        IGovernance.InitiativeState memory initiativeState = IGovernance.InitiativeState({
            voteLQTY: 10e18,
            voteOffset: 1e18,
            vetoLQTY: 0,
            vetoOffset: 0,
            lastEpochClaim: 1
        });

        vm.expectRevert(bytes("InitiativeSwitch: invalid-sender"));
        initiativeSwitch.onAfterAllocateLQTY(epoch, user, userState, allocation, initiativeState);
    }

    function testOnClaimForInitiative() public {
        uint256 boldAmount = 100;
        uint256 epoch = governance.epoch();

        // Mint some BOLD tokens to the initiativeSwitch contract
        deal(address(bold), address(initiativeSwitch), boldAmount);

        vm.prank(address(governance));
        initiativeSwitch.onClaimForInitiative(epoch, boldAmount);

        // TODO
    }

    function testOnClaimForInitiativeRevertsIfNotGovernance() public {
        vm.expectRevert(bytes("InitiativeSwitch: invalid-sender"));
        initiativeSwitch.onClaimForInitiative(5, 100);
    }
}
