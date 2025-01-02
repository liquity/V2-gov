// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IInitiative} from "../src/interfaces/IInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";

contract MockInitiative is IInitiative {
    struct OnAfterAllocateLQTYParams {
        uint256 currentEpoch;
        address user;
        IGovernance.UserState userState;
        IGovernance.Allocation allocation;
        IGovernance.InitiativeState initiativeStat;
    }

    OnAfterAllocateLQTYParams[] public onAfterAllocateLQTYCalls;

    function numOnAfterAllocateLQTYCalls() external view returns (uint256) {
        return onAfterAllocateLQTYCalls.length;
    }

    function onAfterAllocateLQTY(
        uint256 _currentEpoch,
        address _user,
        IGovernance.UserState calldata _userState,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external override {
        onAfterAllocateLQTYCalls.push(
            OnAfterAllocateLQTYParams(_currentEpoch, _user, _userState, _allocation, _initiativeState)
        );
    }

    function onRegisterInitiative(uint256) external override {}
    function onUnregisterInitiative(uint256) external override {}
    function onClaimForInitiative(uint256, uint256) external override {}
}

contract InitiativeHooksTest is MockStakingV1Deployer {
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
    Governance governance;
    MockInitiative initiative;
    address[] noInitiatives; // left empty
    address[] initiatives;
    int256[] votes;
    int256[] vetos;
    address voter;

    function setUp() external {
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

        initiative = new MockInitiative();
        initiatives.push(address(initiative));
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

    function test_OnAfterAllocateLQTY_IsCalled_WhenCastingVotes() external {
        vm.startPrank(voter);
        votes[0] = 123;
        governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(initiative.numOnAfterAllocateLQTYCalls(), 1, "onAfterAllocateLQTY should have been called once");
        (,,, IGovernance.Allocation memory allocation,) = initiative.onAfterAllocateLQTYCalls(0);
        assertEq(allocation.voteLQTY, 123, "wrong voteLQTY 1");

        vm.startPrank(voter);
        votes[0] = 456;
        governance.allocateLQTY(initiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(initiative.numOnAfterAllocateLQTYCalls(), 3, "onAfterAllocateLQTY should have been called twice more");
        (,,, allocation,) = initiative.onAfterAllocateLQTYCalls(1);
        assertEq(allocation.voteLQTY, 0, "wrong voteLQTY 2");
        (,,, allocation,) = initiative.onAfterAllocateLQTYCalls(2);
        assertEq(allocation.voteLQTY, 456, "wrong voteLQTY 3");
    }

    function test_OnAfterAllocateLQTY_IsNotCalled_WhenCastingVetos() external {
        vm.startPrank(voter);
        vetos[0] = 123;
        governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(initiative.numOnAfterAllocateLQTYCalls(), 0, "onAfterAllocateLQTY should not have been called once");
    }

    function test_OnAfterAllocateLQTY_IsCalledOnceWithZeroVotes_WhenCastingVetosAfterHavingCastVotes() external {
        vm.startPrank(voter);
        votes[0] = 123;
        governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(initiative.numOnAfterAllocateLQTYCalls(), 1, "onAfterAllocateLQTY should have been called once");

        vm.startPrank(voter);
        votes[0] = 0;
        vetos[0] = 456;
        governance.allocateLQTY(initiatives, initiatives, votes, vetos);
        vm.stopPrank();

        assertEq(initiative.numOnAfterAllocateLQTYCalls(), 2, "onAfterAllocateLQTY should have been called once more");
        (,,, IGovernance.Allocation memory allocation,) = initiative.onAfterAllocateLQTYCalls(1);
        assertEq(allocation.voteLQTY, 0, "wrong voteLQTY");
    }
}
