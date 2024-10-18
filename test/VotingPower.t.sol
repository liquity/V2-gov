// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILQTY} from "../src/interfaces/ILQTY.sol";

import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {UserProxy} from "../src/UserProxy.sol";

import {PermitParams} from "../src/utils/Types.sol";

import {MockInitiative} from "./mocks/MockInitiative.sol";

contract VotingPowerTest is Test {
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

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        baseInitiative1 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative2 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative3 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
                address(lusd),
                address(lqty)
            )
        );

        initialInitiatives.push(baseInitiative1);
        initialInitiatives.push(baseInitiative2);

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
                epochStart: uint32(block.timestamp - EPOCH_DURATION),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
    }

    /// TODO: Deallocating doesn't change the avg for the initiative though
    /// So if you deallocate I think it will desynch the math
    
    /// Allocate half of everything a TS X
    /// Next epoch add more, change the TS
    /// Allocate rest to another initiative
    /// Sum the total value

    /// Compare with removing all and re-allocating all at the 2nd epoch


    //// Compare the relative power per epoch
    /// As in, one epoch should reliably increase the power by X amt
    // forge test --match-test test_allocation_avg_ts_mismatch -vv
    function test_allocation_avg_ts_mismatch() public {
        uint256 snapshot0 = vm.snapshot();

        uint256 snapshotBefore = vm.snapshot();

        vm.startPrank(user);
        // =========== epoch 1 ==================
        // 1. user stakes lqty
        int88 lqtyAmount = 2e18;
        _stakeLQTY(user, uint88(lqtyAmount / 2));

        // user allocates to baseInitiative1
        _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
        (, uint32 averageStakingTimestamp1) = governance.userStates(user);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch


        // Remainer
        _stakeLQTY(user, uint88(lqtyAmount / 2));
        _allocate(address(baseInitiative2), lqtyAmount / 2, 0); // 50% to it

        (, uint32 averageStakingTimestamp2) = governance.userStates(user);

        assertGt(averageStakingTimestamp2, averageStakingTimestamp1, "Time increase");

        // Get TS for "exploit"
        uint256 avgTs1 = _getAverageTS(baseInitiative1);
        uint256 avgTs2 = _getAverageTS(baseInitiative2);
        assertGt(avgTs2, avgTs1, "TS in initiative is increased");

        // Check if Resetting will fix the issue

        _allocate(address(baseInitiative1), -(lqtyAmount / 2), 0);
        _allocate(address(baseInitiative2), -(lqtyAmount / 2), 0);

        _allocate(address(baseInitiative1), (lqtyAmount / 2), 0);
        _allocate(address(baseInitiative2), (lqtyAmount / 2), 0);

        uint256 avgTs_reset_1 = _getAverageTS(baseInitiative1);
        uint256 avgTs_reset_2 = _getAverageTS(baseInitiative2);


        // Intuition, Delta time * LQTY = POWER
        vm.revertTo(snapshotBefore);

        // Compare against
        // Deposit 1 on epoch 1
        // Deposit 2 on epoch 2
        // Vote on epoch 2 exclusively
        _stakeLQTY(user, uint88(lqtyAmount / 2));

        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch
        _stakeLQTY(user, uint88(lqtyAmount / 2));
        _allocate(address(baseInitiative2), lqtyAmount / 2, 0); // 50% to it
        _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it

        uint256 avgTs1_diff = _getAverageTS(baseInitiative1);
        uint256 avgTs2_diff = _getAverageTS(baseInitiative2);
        assertEq(avgTs2_diff, avgTs1_diff, "TS in initiative is increased");

        assertEq(avgTs2_diff, avgTs2, "Ts2 is same");
        assertGt(avgTs1_diff, avgTs1, "Ts1 lost the power");

        assertEq(avgTs_reset_1, avgTs1_diff, "Same as diff means it does reset");
        assertEq(avgTs_reset_2, avgTs2_diff, "Same as diff means it does reset");
    }


    // Check if Flashloan can be used to cause issues?
    // A flashloan would cause issues in the measure in which it breaks any specific property
    // Or expectation

    // Remove votes
    // Removing votes would force you to exclusively remove
    // You can always remove at any time afacit
    // Removing just updates that + the weights
    // The weights are the avg time * the number


    function _getAverageTS(address initiative) internal returns (uint256) {
        (
            ,
            ,
            uint32 averageStakingTimestampVoteLQTY,
            ,
            
        ) = governance.initiativeStates(initiative);

        return averageStakingTimestampVoteLQTY;
    }

    // // checking if deallocating changes the averageStakingTimestamp
    // function test_deallocating_decreases_avg_timestamp() public {
    //     // =========== epoch 1 ==================
    //     governance = new Governance(
    //         address(lqty),
    //         address(lusd),
    //         address(stakingV1),
    //         address(lusd),
    //         IGovernance.Configuration({
    //             registrationFee: REGISTRATION_FEE,
    //             registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
    //             unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
    //             registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
    //             unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
    //             votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
    //             minClaim: MIN_CLAIM,
    //             minAccrual: MIN_ACCRUAL,
    //             epochStart: uint32(block.timestamp),
    //             epochDuration: EPOCH_DURATION,
    //             epochVotingCutoff: EPOCH_VOTING_CUTOFF
    //         }),
    //         initialInitiatives
    //     );

    //     // 1. user stakes lqty
    //     uint88 lqtyAmount = 1e18;
    //     _stakeLQTY(user, lqtyAmount);

    //     // =========== epoch 2 (start) ==================
    //     // 2. user allocates in epoch 2 for initiative
    //     vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

    //     _allocateLQTY(user, lqtyAmount);

    //     // =========== epoch 3 ==================
    //     // 3. warp to third epoch and check voting power
    //     vm.warp(block.timestamp + EPOCH_DURATION);
    //     console2.log("current epoch A: ", governance.epoch());
    //     governance.snapshotVotesForInitiative(baseInitiative1);

    //     (,uint32 averageStakingTimestampBefore) = governance.userStates(user);

    //     _deAllocateLQTY(user, lqtyAmount);

    //     (,uint32 averageStakingTimestampAfter) = governance.userStates(user);
    //     assertEq(averageStakingTimestampBefore, averageStakingTimestampAfter);
    // }


    function _stakeLQTY(address _user, uint88 amount) internal {
        address userProxy = governance.deriveUserProxyAddress(_user);
        lqty.approve(address(userProxy), amount);

        governance.depositLQTY(amount);
    }


    function _allocate(address initiative, int88 votes, int88 vetos) internal {
        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = votes;
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = vetos;
        
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);
    }
}
