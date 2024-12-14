// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILUSD} from "../src/interfaces/ILUSD.sol";
import {ILQTY} from "../src/interfaces/ILQTY.sol";
import {ILQTYStaking} from "../src/interfaces/ILQTYStaking.sol";

import {Governance} from "../src/Governance.sol";
import {UserProxy} from "../src/UserProxy.sol";

import {MaliciousInitiative} from "./mocks/MaliciousInitiative.sol";
import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";
import "./constants.sol";

abstract contract GovernanceAttacksTest is Test {
    ILQTY internal lqty;
    ILUSD internal lusd;
    ILQTYStaking internal stakingV1;

    address internal constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address internal constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address internal constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint256 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    MaliciousInitiative private maliciousInitiative1;
    MaliciousInitiative private maliciousInitiative2;
    MaliciousInitiative private eoaInitiative;

    function setUp() public virtual {
        maliciousInitiative1 = new MaliciousInitiative();
        maliciousInitiative2 = new MaliciousInitiative();
        eoaInitiative = MaliciousInitiative(address(0x123123123123));

        initialInitiatives.push(address(maliciousInitiative1));

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            // backdate by 2 epochs to ensure new initiatives can be registered from the start
            epochStart: uint256(block.timestamp - 2 * EPOCH_DURATION),
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance(
            address(lqty), address(lusd), address(stakingV1), address(lusd), config, address(this), initialInitiatives
        );
    }

    // All calls should never revert due to malicious initiative
    function test_all_revert_attacks_hardcoded() public {
        vm.startPrank(user);

        // should not revert if the user doesn't have a UserProxy deployed yet
        address userProxy = governance.deriveUserProxyAddress(user);
        lqty.approve(address(userProxy), 1e18);

        // deploy and deposit 1 LQTY
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (,, uint256 allocatedLQTY, uint256 allocatedOffset) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        // First deposit should have an unallocated offset of timestamp * deposit
        assertEq(allocatedOffset, 0);
        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        address maliciousWhale = address(0xb4d);
        deal(address(lusd), maliciousWhale, 2000e18);
        vm.startPrank(maliciousWhale);
        lusd.approve(address(governance), type(uint256).max);

        /// === REGISTRATION REVERTS === ///
        uint256 registerNapshot = vm.snapshot();

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.REGISTER, MaliciousInitiative.RevertType.THROW
        );
        governance.registerInitiative(address(maliciousInitiative2));
        vm.revertTo(registerNapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.REGISTER, MaliciousInitiative.RevertType.OOG
        );
        governance.registerInitiative(address(maliciousInitiative2));
        vm.revertTo(registerNapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.REGISTER, MaliciousInitiative.RevertType.RETURN_BOMB
        );
        governance.registerInitiative(address(maliciousInitiative2));
        vm.revertTo(registerNapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.REGISTER, MaliciousInitiative.RevertType.REVERT_BOMB
        );
        governance.registerInitiative(address(maliciousInitiative2));
        vm.revertTo(registerNapshot);

        // Reset and continue
        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.REGISTER, MaliciousInitiative.RevertType.NONE
        );
        governance.registerInitiative(address(maliciousInitiative2));

        // Register EOA
        governance.registerInitiative(address(eoaInitiative));

        vm.stopPrank();

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = address(maliciousInitiative2);
        initiatives[1] = address(eoaInitiative);
        int256[] memory deltaVoteLQTY = new int256[](2);
        deltaVoteLQTY[0] = 5e17;
        deltaVoteLQTY[1] = 5e17;
        int256[] memory deltaVetoLQTY = new int256[](2);

        /// === Allocate LQTY REVERTS === ///
        uint256 allocateSnapshot = vm.snapshot();

        vm.startPrank(user);
        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.THROW
        );
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.OOG
        );
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.RETURN_BOMB
        );
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.REVERT_BOMB
        );
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.NONE
        );
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        /// === Claim for initiative REVERTS === ///
        uint256 claimShapsnot = vm.snapshot();

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.CLAIM, MaliciousInitiative.RevertType.THROW
        );
        governance.claimForInitiative(address(maliciousInitiative2));
        vm.revertTo(claimShapsnot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.CLAIM, MaliciousInitiative.RevertType.OOG
        );
        governance.claimForInitiative(address(maliciousInitiative2));
        vm.revertTo(claimShapsnot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.CLAIM, MaliciousInitiative.RevertType.RETURN_BOMB
        );
        governance.claimForInitiative(address(maliciousInitiative2));
        vm.revertTo(claimShapsnot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.CLAIM, MaliciousInitiative.RevertType.REVERT_BOMB
        );
        governance.claimForInitiative(address(maliciousInitiative2));
        vm.revertTo(claimShapsnot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.CLAIM, MaliciousInitiative.RevertType.NONE
        );
        governance.claimForInitiative(address(maliciousInitiative2));

        governance.claimForInitiative(address(eoaInitiative));

        /// === Unregister Reverts === ///

        vm.startPrank(user);
        initiativesToReset = new address[](2);
        initiativesToReset[0] = address(maliciousInitiative2);
        initiativesToReset[1] = address(eoaInitiative);
        initiatives = new address[](1);
        initiatives[0] = address(maliciousInitiative1);
        deltaVoteLQTY = new int256[](1);
        deltaVoteLQTY[0] = 5e17;
        deltaVetoLQTY = new int256[](1);
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);

        (Governance.VoteSnapshot memory v, Governance.InitiativeVoteSnapshot memory initData) =
            governance.snapshotVotesForInitiative(address(maliciousInitiative2));

        // Inactive for 4 epochs
        // Add another proposal

        vm.warp(block.timestamp + governance.EPOCH_DURATION() * 5);

        /// @audit needs 5?
        (v, initData) = governance.snapshotVotesForInitiative(address(maliciousInitiative2));
        uint256 unregisterSnapshot = vm.snapshot();

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.UNREGISTER, MaliciousInitiative.RevertType.THROW
        );
        governance.unregisterInitiative(address(maliciousInitiative2));
        vm.revertTo(unregisterSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.UNREGISTER, MaliciousInitiative.RevertType.OOG
        );
        governance.unregisterInitiative(address(maliciousInitiative2));
        vm.revertTo(unregisterSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.UNREGISTER, MaliciousInitiative.RevertType.RETURN_BOMB
        );
        governance.unregisterInitiative(address(maliciousInitiative2));
        vm.revertTo(unregisterSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.UNREGISTER, MaliciousInitiative.RevertType.REVERT_BOMB
        );
        governance.unregisterInitiative(address(maliciousInitiative2));
        vm.revertTo(unregisterSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.UNREGISTER, MaliciousInitiative.RevertType.NONE
        );
        governance.unregisterInitiative(address(maliciousInitiative2));

        governance.unregisterInitiative(address(eoaInitiative));
    }
}

contract MockedGovernanceAttacksTest is GovernanceAttacksTest, MockStakingV1Deployer {
    function setUp() public override {
        (MockStakingV1 mockStakingV1, MockERC20Tester mockLQTY, MockERC20Tester mockLUSD) = deployMockStakingV1();

        mockLQTY.mint(user, 1e18);
        mockLUSD.mint(lusdHolder, 10_000e18);

        lqty = mockLQTY;
        lusd = mockLUSD;
        stakingV1 = mockStakingV1;

        super.setUp();
    }
}

contract ForkedGovernanceAttacksTest is GovernanceAttacksTest {
    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        lqty = ILQTY(MAINNET_LQTY);
        lusd = ILUSD(MAINNET_LUSD);
        stakingV1 = ILQTYStaking(MAINNET_LQTY_STAKING);

        super.setUp();
    }
}
