// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {Governance} from "../src/Governance.sol";
import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";

// These tests demonstrate that by deploying `Governance` with `epochStart` set one `EPOCH_DURATION` in the past:
//  - initial initiatives can immediately be voted on,
//  - registration of new initiatives is disabled for one epoch.
//
// The reason we want to initially disable registration is that there's not vote snapshot to base the registration
// threshold upon, thus registration would otherwise be possible without having any LQTY staked.
contract DeploymentTest is MockStakingV1Deployer {
    uint32 constant START_TIME = 1732873631;
    uint32 constant EPOCH_DURATION = 7 days;
    uint128 constant REGISTRATION_FEE = 1 ether;

    address constant deployer = address(uint160(uint256(keccak256("deployer"))));
    address constant voter = address(uint160(uint256(keccak256("voter"))));
    address constant registrant = address(uint160(uint256(keccak256("registrant"))));
    address constant initialInitiative = address(uint160(uint256(keccak256("initialInitiative"))));
    address constant newInitiative = address(uint160(uint256(keccak256("newInitiative"))));

    IGovernance.Configuration config = IGovernance.Configuration({
        registrationFee: REGISTRATION_FEE,
        registrationThresholdFactor: 0.01 ether,
        unregistrationThresholdFactor: 4 ether,
        unregistrationAfterEpochs: 4,
        votingThresholdFactor: 0.04 ether,
        minClaim: 0,
        minAccrual: 0,
        epochStart: START_TIME - EPOCH_DURATION,
        epochDuration: EPOCH_DURATION,
        epochVotingCutoff: EPOCH_DURATION - 1 days
    });

    MockStakingV1 stakingV1;
    MockERC20Tester lqty;
    MockERC20Tester lusd;
    MockERC20Tester bold;
    Governance governance;

    address[] initiativesToReset;
    address[] initiatives;
    int256[] votes;
    int256[] vetos;

    function setUp() external {
        vm.warp(START_TIME);

        vm.label(deployer, "deployer");
        vm.label(voter, "voter");
        vm.label(registrant, "registrant");
        vm.label(initialInitiative, "initialInitiative");
        vm.label(newInitiative, "newInitiative");

        (stakingV1, lqty, lusd) = deployMockStakingV1();
        bold = new MockERC20Tester("BOLD Stablecoin", "BOLD");

        initiatives.push(initialInitiative);

        vm.prank(deployer);
        governance = new Governance({
            _lqty: address(lqty),
            _lusd: address(lusd),
            _stakingV1: address(stakingV1),
            _bold: address(bold),
            _config: config,
            _owner: deployer,
            _initiatives: initiatives
        });

        vm.label(governance.deriveUserProxyAddress(voter), "voterProxy");
    }

    function test_AtStart_WeAreInEpoch2() external view {
        assertEq(governance.epoch(), 2, "We should start in epoch #2");
    }

    function test_OneEpochLater_WeAreInEpoch3() external {
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(governance.epoch(), 3, "We should be in epoch #3");
    }

    function test_AtStart_CanVoteOnInitialInitiative() external {
        _voteOnInitiative();

        uint256 boldAccrued = 1 ether;
        bold.mint(address(governance), boldAccrued);
        vm.warp(block.timestamp + EPOCH_DURATION);

        governance.claimForInitiative(initialInitiative);
        assertEqDecimal(bold.balanceOf(initialInitiative), boldAccrued, 18, "Initiative should have received BOLD");
    }

    function test_AtStart_CannotRegisterNewInitiative() external {
        _registerNewInitiative({expectRevertReason: "Governance: registration-not-yet-enabled"});
    }

    function test_OneEpochLater_WhenNoOneVotedDuringEpoch2_CanRegisterNewInitiativeWithNoLQTY() external {
        vm.warp(block.timestamp + EPOCH_DURATION);
        _registerNewInitiative();
    }

    function test_OneEpochLater_WhenSomeoneVotedDuringEpoch2_CannotRegisterNewInitiativeWithNoLQTY() external {
        _voteOnInitiative();
        vm.warp(block.timestamp + EPOCH_DURATION);
        _registerNewInitiative({expectRevertReason: "Governance: insufficient-lqty"});
        _depositLQTY(); // Only LQTY deposited during previous epoch counts
        _registerNewInitiative({expectRevertReason: "Governance: insufficient-lqty"});
    }

    function test_OneEpochLater_WhenSomeoneVotedDuringEpoch2_CanRegisterNewInitiativeWithSufficientLQTY() external {
        _voteOnInitiative();
        _depositLQTY();
        vm.warp(block.timestamp + EPOCH_DURATION);
        _registerNewInitiative();
    }

    /////////////
    // Helpers //
    /////////////

    function _voteOnInitiative() internal {
        uint256 lqtyAmount = 1 ether;
        lqty.mint(voter, lqtyAmount);

        votes.push(int256(lqtyAmount));
        vetos.push(0);

        vm.startPrank(voter);
        lqty.approve(governance.deriveUserProxyAddress(voter), lqtyAmount);
        governance.depositLQTY(lqtyAmount);
        governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
        vm.stopPrank();

        delete votes;
        delete vetos;
    }

    function _registerNewInitiative() internal {
        _registerNewInitiative("");
    }

    function _registerNewInitiative(bytes memory expectRevertReason) internal {
        bold.mint(registrant, REGISTRATION_FEE);
        vm.startPrank(registrant);
        bold.approve(address(governance), REGISTRATION_FEE);
        if (expectRevertReason.length > 0) vm.expectRevert(expectRevertReason);
        governance.registerInitiative(newInitiative);
        vm.stopPrank();
    }

    function _depositLQTY() internal {
        uint256 lqtyAmount = 1 ether;
        lqty.mint(registrant, lqtyAmount);
        vm.startPrank(registrant);
        lqty.approve(governance.deriveUserProxyAddress(registrant), lqtyAmount);
        governance.depositLQTY(lqtyAmount);
        vm.stopPrank();
    }
}
