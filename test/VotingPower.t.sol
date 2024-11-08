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
            address(this),
            initialInitiatives
        );
    }

    /// Compare with removing all and re-allocating all at the 2nd epoch
    // forge test --match-test test_math_soundness -vv
    function test_math_soundness() public {
        // Given a Multiplier, I can wait 8 times more time
        // Or use 8 times more amt
        uint8 multiplier = 2;

        uint88 lqtyAmount = 1e18;

        uint256 powerInTheFuture = governance.lqtyToVotes(lqtyAmount, multiplier + 1, 1);
        // Amt when delta is 1
        // 0 when delta is 0
        uint256 powerFromMoreDeposits =
            governance.lqtyToVotes(lqtyAmount * multiplier, uint32(block.timestamp + 1), uint32(block.timestamp));

        assertEq(powerInTheFuture, powerFromMoreDeposits, "Same result");
    }

    function test_math_soundness_fuzz(uint32 multiplier) public {
        vm.assume(multiplier < type(uint32).max - 1);
        uint88 lqtyAmount = 1e10;

        uint256 powerInTheFuture = governance.lqtyToVotes(lqtyAmount, multiplier + 1, 1);

        // Amt when delta is 1
        // 0 when delta is 0
        uint256 powerFromMoreDeposits =
            governance.lqtyToVotes(lqtyAmount * multiplier, uint32(block.timestamp + 1), uint32(block.timestamp));

        assertEq(powerInTheFuture, powerFromMoreDeposits, "Same result");
    }

    function _averageAge(uint32 _currentTimestamp, uint32 _averageTimestamp) internal pure returns (uint32) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function _calculateAverageTimestamp(
        uint32 _prevOuterAverageTimestamp,
        uint32 _newInnerAverageTimestamp,
        uint88 _prevLQTYBalance,
        uint88 _newLQTYBalance
    ) internal view returns (uint32) {
        if (_newLQTYBalance == 0) return 0;

        uint32 prevOuterAverageAge = _averageAge(uint32(block.timestamp), _prevOuterAverageTimestamp);
        uint32 newInnerAverageAge = _averageAge(uint32(block.timestamp), _newInnerAverageTimestamp);

        uint88 newOuterAverageAge;
        if (_prevLQTYBalance <= _newLQTYBalance) {
            uint88 deltaLQTY = _newLQTYBalance - _prevLQTYBalance;
            uint240 prevVotes = uint240(_prevLQTYBalance) * uint240(prevOuterAverageAge);
            uint240 newVotes = uint240(deltaLQTY) * uint240(newInnerAverageAge);
            uint240 votes = prevVotes + newVotes;
            newOuterAverageAge = uint32(votes / uint240(_newLQTYBalance));
        } else {
            uint88 deltaLQTY = _prevLQTYBalance - _newLQTYBalance;
            uint240 prevVotes = uint240(_prevLQTYBalance) * uint240(prevOuterAverageAge);
            uint240 newVotes = uint240(deltaLQTY) * uint240(newInnerAverageAge);
            uint240 votes = (prevVotes >= newVotes) ? prevVotes - newVotes : 0;
            newOuterAverageAge = uint32(votes / uint240(_newLQTYBalance));
        }

        if (newOuterAverageAge > block.timestamp) return 0;
        return uint32(block.timestamp - newOuterAverageAge);
    }

    // This test prepares for comparing votes and vetos for state
    // forge test --match-test test_we_can_compare_votes_and_vetos -vv
    function test_we_can_compare_votes_and_vetos() public {
        uint32 current_time = 123123123;
        vm.warp(current_time);
        // State at X
        // State made of X and Y
        uint32 time = current_time - 124;
        uint88 votes = 124;
        uint240 power = governance.lqtyToVotes(votes, current_time, time);

        assertEq(power, (_averageAge(current_time, time)) * votes, "simple product");

        // if it's a simple product we have the properties of multiplication, we can get back the value by dividing the tiem
        uint88 resultingVotes = uint88(power / _averageAge(current_time, time));

        assertEq(resultingVotes, votes, "We can get it back");

        // If we can get it back, then we can also perform other operations like addition and subtraction
        // Easy when same TS

        // // But how do we sum stuff with different TS?
        // // We need to sum the total and sum the % of average ts
        uint88 votes_2 = 15;
        uint32 time_2 = current_time - 15;

        uint240 power_2 = governance.lqtyToVotes(votes_2, current_time, time_2);

        uint240 total_power = power + power_2;

        assertLe(total_power, uint240(type(uint88).max), "LT");

        uint88 total_liquity = votes + votes_2;

        uint32 avgTs = _calculateAverageTimestamp(time, time_2, votes, total_liquity);

        console.log("votes", votes);
        console.log("time", current_time - time);
        console.log("power", power);

        console.log("votes_2", votes_2);
        console.log("time_2", current_time - time_2);
        console.log("power_2", power_2);

        uint256 total_power_from_avg = governance.lqtyToVotes(total_liquity, current_time, avgTs);

        console.log("total_liquity", total_liquity);
        console.log("avgTs", current_time - avgTs);
        console.log("total_power_from_avg", total_power_from_avg);

        // Now remove the same math so we show that the rounding can be weaponized, let's see

        // WTF

        // Prev, new, prev new
        // AVG TS is the prev outer
        // New Inner is time
        uint32 attacked_avg_ts = _calculateAverageTimestamp(
            avgTs,
            time_2, // User removes their time
            total_liquity,
            votes // Votes = total_liquity - Vote_2
        );

        // NOTE: != time due to rounding error
        console.log("attacked_avg_ts", current_time - attacked_avg_ts);

        // BASIC VOTING TEST
        // AFTER VOTING POWER IS X
        // AFTER REMOVING VOTING IS 0

        // Add a middle of random shit
        // Show that the math remains sound

        // Off by 40 BPS????? WAYY TOO MUCH | SOMETHING IS WRONG

        // It doesn't sum up exactly becasue of rounding errors
        // But we need the rounding error to be in favour of the protocol
        // And currently they are not
        assertEq(total_power, total_power_from_avg, "Sums up");

        // From those we can find the average timestamp
        uint88 resultingReturnedVotes = uint88(total_power_from_avg / _averageAge(current_time, time));
        assertEq(resultingReturnedVotes, total_liquity, "Lqty matches");
    }

    // forge test --match-test test_crit_user_can_dilute_total_votes -vv
    function test_crit_user_can_dilute_total_votes() public {
        // User A deposits normaly
        vm.startPrank(user);

        _stakeLQTY(user, 124);

        vm.warp(block.timestamp + 124 - 15);

        vm.startPrank(user2);
        _stakeLQTY(user2, 15);

        vm.warp(block.timestamp + 15);

        vm.startPrank(user);
        _allocate(address(baseInitiative1), 124, 0);
        uint256 user1_avg = _getAverageTS(baseInitiative1);

        vm.startPrank(user2);
        _allocate(address(baseInitiative1), 15, 0);
        uint256 both_avg = _getAverageTS(baseInitiative1);
        _allocate(address(baseInitiative1), 0, 0);

        uint256 griefed_avg = _getAverageTS(baseInitiative1);

        uint256 vote_power_1 = governance.lqtyToVotes(124, uint32(block.timestamp), uint32(user1_avg));
        uint256 vote_power_2 = governance.lqtyToVotes(124, uint32(block.timestamp), uint32(griefed_avg));

        console.log("vote_power_1", vote_power_1);
        console.log("vote_power_2", vote_power_2);

        // assertEq(user1_avg, griefed_avg, "same avg"); // BREAKS, OFF BY ONE

        // Causes a loss of power of 1 second per time this is done

        vm.startPrank(user);
        _allocate(address(baseInitiative1), 0, 0);

        uint256 final_avg = _getAverageTS(baseInitiative1);
        console.log("final_avg", final_avg);

        // This is not an issue, except for bribes, bribes can get the last claimer DOSS
    }

    // forge test --match-test test_can_we_spam_to_revert -vv
    function test_can_we_spam_to_revert() public {
        // User A deposits normaly
        vm.startPrank(user);

        _stakeLQTY(user, 124);

        vm.warp(block.timestamp + 124);

        vm.startPrank(user2);
        _stakeLQTY(user2, 15);

        vm.startPrank(user);
        _allocate(address(baseInitiative1), 124, 0);
        uint256 user1_avg = _getAverageTS(baseInitiative1);

        vm.startPrank(user2);
        _allocate(address(baseInitiative1), 15, 0);
        uint256 both_avg = _getAverageTS(baseInitiative1);
        _allocate(address(baseInitiative1), 0, 0);

        uint256 griefed_avg = _getAverageTS(baseInitiative1);
        console.log("griefed_avg", griefed_avg);
        console.log("block.timestamp", block.timestamp);

        vm.startPrank(user2);
        _allocate(address(baseInitiative1), 15, 0);
        _allocate(address(baseInitiative1), 0, 0);

        uint256 ts = _getAverageTS(baseInitiative1);
        uint256 delta = block.timestamp - ts;
        console.log("griefed_avg", ts);
        console.log("delta", delta);
        console.log("block.timestamp", block.timestamp);

        uint256 i;
        while (i++ < 122) {
            _allocate(address(baseInitiative1), 15, 0);
            _allocate(address(baseInitiative1), 0, 0);
        }

        ts = _getAverageTS(baseInitiative1);
        delta = block.timestamp - ts;
        console.log("griefed_avg", ts);
        console.log("delta", delta);
        console.log("block.timestamp", block.timestamp);

        // One more time
        _allocate(address(baseInitiative1), 15, 0);
        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative1), 15, 0);
        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative1), 15, 0);
        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative1), 15, 0);

        /// NOTE: Keep 1 wei to keep rounding error
        _allocate(address(baseInitiative1), 1, 0);

        ts = _getAverageTS(baseInitiative1);
        console.log("griefed_avg", ts);

        vm.startPrank(user);
        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative1), 124, 0);

        ts = _getAverageTS(baseInitiative1);
        console.log("end_ts", ts);
    }

    // forge test --match-test test_basic_reset_flow -vv
    function test_basic_reset_flow() public {
        uint256 snapshot0 = vm.snapshot();

        uint256 snapshotBefore = vm.snapshot();

        vm.startPrank(user);
        // =========== epoch 1 ==================
        // 1. user stakes lqty
        int88 lqtyAmount = 2e18;
        _stakeLQTY(user, uint88(lqtyAmount / 2));

        // user allocates to baseInitiative1
        _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp1) = governance.userStates(user);
        assertEq(allocatedLQTY, uint88(lqtyAmount / 2), "half");

        _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
        assertEq(allocatedLQTY, uint88(lqtyAmount / 2), "still half, the math is absolute now");
    }

    // forge test --match-test test_cutoff_logic -vv
    function test_cutoff_logic() public {
        uint256 snapshot0 = vm.snapshot();

        uint256 snapshotBefore = vm.snapshot();

        vm.startPrank(user);
        // =========== epoch 1 ==================
        // 1. user stakes lqty
        int88 lqtyAmount = 2e18;
        _stakeLQTY(user, uint88(lqtyAmount));

        // user allocates to baseInitiative1
        _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp1) = governance.userStates(user);
        assertEq(allocatedLQTY, uint88(lqtyAmount / 2), "Half");

        // Go to Cutoff
        // See that you can reduce
        // See that you can Veto as much as you want
        vm.warp(block.timestamp + (EPOCH_DURATION) - governance.EPOCH_VOTING_CUTOFF() + 1); // warp to end of second epoch before the voting cutoff

        // Go to end of epoch, lazy math
        while (!(governance.secondsWithinEpoch() > governance.EPOCH_VOTING_CUTOFF())) {
            vm.warp(block.timestamp + 6 hours);
        }
        assertTrue(
            governance.secondsWithinEpoch() > governance.EPOCH_VOTING_CUTOFF(), "We should not be able to vote more"
        );

        vm.expectRevert(); // cannot allocate more
        _allocate(address(baseInitiative1), lqtyAmount, 0);

        // Can allocate less
        _allocate(address(baseInitiative1), lqtyAmount / 2 - 1, 0);

        // Can Veto more than allocate
        _allocate(address(baseInitiative1), 0, lqtyAmount);
    }

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

        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative2), 0, 0);

        _allocate(address(baseInitiative1), 0, 0);
        _allocate(address(baseInitiative2), 0, 0);

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
        // assertEq(avgTs2_diff, avgTs1_diff, "TS in initiative is increased");
        assertGt(avgTs1_diff, avgTs2_diff, "TS in initiative is increased");

        assertLt(avgTs2_diff, avgTs2, "Ts2 is same");
        assertGt(avgTs1_diff, avgTs1, "Ts1 lost the power");

        assertLt(avgTs_reset_1, avgTs1_diff, "Same as diff means it does reset");
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
        (,, uint32 averageStakingTimestampVoteLQTY,,) = governance.initiativeStates(initiative);

        return averageStakingTimestampVoteLQTY;
    }

    function _stakeLQTY(address _user, uint88 amount) internal {
        address userProxy = governance.deriveUserProxyAddress(_user);
        lqty.approve(address(userProxy), amount);

        governance.depositLQTY(amount);
    }

    function _allocate(address initiative, int88 votes, int88 vetos) internal {
        address[] memory initiativesToReset = new address[](3);
        initiativesToReset[0] = baseInitiative1;
        initiativesToReset[1] = baseInitiative2;
        initiativesToReset[2] = baseInitiative3;
        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = votes;
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = vetos;

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
    }
}
