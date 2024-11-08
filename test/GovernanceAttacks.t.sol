// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {UserProxy} from "../src/UserProxy.sol";

import {MaliciousInitiative} from "./mocks/MaliciousInitiative.sol";

contract GovernanceTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant REGISTRATION_WARM_UP_PERIOD = 4;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    MaliciousInitiative private maliciousInitiative1;
    MaliciousInitiative private maliciousInitiative2;
    MaliciousInitiative private eoaInitiative;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        maliciousInitiative1 = new MaliciousInitiative();
        maliciousInitiative2 = new MaliciousInitiative();
        eoaInitiative = MaliciousInitiative(address(0x123123123123));

        initialInitiatives.push(address(maliciousInitiative1));

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
            address(this),
            initialInitiatives
        );
    }

    // forge test --match-test test_all_revert_attacks_hardcoded -vv
    // All calls should never revert due to malicious initiative
    function test_all_revert_attacks_hardcoded() public {
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.startPrank(user);

        // should not revert if the user doesn't have a UserProxy deployed yet
        address userProxy = governance.deriveUserProxyAddress(user);
        lqty.approve(address(userProxy), 1e18);

        // deploy and deposit 1 LQTY
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        // first deposit should have an averageStakingTimestamp if block.timestamp
        assertEq(averageStakingTimestamp, block.timestamp);
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

        vm.startPrank(user);
        address[] memory initiatives = new address[](2);
        initiatives[0] = address(maliciousInitiative2);
        initiatives[1] = address(eoaInitiative);
        int88[] memory deltaVoteLQTY = new int88[](2);
        deltaVoteLQTY[0] = 5e17;
        deltaVoteLQTY[1] = 5e17;
        int88[] memory deltaVetoLQTY = new int88[](2);

        /// === Allocate LQTY REVERTS === ///
        uint256 allocateSnapshot = vm.snapshot();

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.THROW
        );
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.OOG
        );
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.RETURN_BOMB
        );
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.REVERT_BOMB
        );
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        vm.revertTo(allocateSnapshot);

        maliciousInitiative2.setRevertBehaviour(
            MaliciousInitiative.FunctionType.ALLOCATE, MaliciousInitiative.RevertType.NONE
        );
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);

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
        initiatives = new address[](3);
        initiatives[0] = address(maliciousInitiative2);
        initiatives[1] = address(eoaInitiative);
        initiatives[2] = address(maliciousInitiative1);
        deltaVoteLQTY = new int88[](3);
        deltaVoteLQTY[0] = 0;
        deltaVoteLQTY[1] = 0;
        deltaVoteLQTY[2] = 5e17;
        deltaVetoLQTY = new int88[](3);
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);

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
