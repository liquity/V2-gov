// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";

// import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// import {IGovernance} from "../src/interfaces/IGovernance.sol";
// import {ILQTYStaking} from "../src/interfaces/ILQTYStaking.sol";

// import {BribeInitiative} from "../src/BribeInitiative.sol";
// import {Governance} from "../src/Governance.sol";

// import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
// import {MockStakingV1} from "./mocks/MockStakingV1.sol";
// import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";
// import "./constants.sol";

// abstract contract VotingPowerTest is Test {
//     IERC20 internal lqty;
//     IERC20 internal lusd;
//     ILQTYStaking internal stakingV1;

//     address internal constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
//     address internal constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
//     address internal constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

//     uint256 private constant REGISTRATION_FEE = 1e18;
//     uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
//     uint256 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
//     uint256 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
//     uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
//     uint256 private constant MIN_CLAIM = 500e18;
//     uint256 private constant MIN_ACCRUAL = 1000e18;
//     uint256 private constant EPOCH_DURATION = 604800;
//     uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

//     Governance private governance;
//     address[] private initialInitiatives;
//     address private baseInitiative1;

//     function setUp() public virtual {
//         IGovernance.Configuration memory config = IGovernance.Configuration({
//             registrationFee: REGISTRATION_FEE,
//             registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
//             unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
//             unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
//             votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
//             minClaim: MIN_CLAIM,
//             minAccrual: MIN_ACCRUAL,
//             epochStart: uint32(block.timestamp - EPOCH_DURATION),
//             epochDuration: EPOCH_DURATION,
//             epochVotingCutoff: EPOCH_VOTING_CUTOFF
//         });

//         governance = new Governance(
//             address(lqty), address(lusd), address(stakingV1), address(lusd), config, address(this), new address[](0)
//         );

//         baseInitiative1 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
//         initialInitiatives.push(baseInitiative1);

//         governance.registerInitialInitiatives(initialInitiatives);
//     }

//     /// Compare with removing all and re-allocating all at the 2nd epoch
//     // forge test --match-test test_math_soundness -vv
//     function test_math_soundness() public {
//         // Given a Multiplier, I can wait 8 times more time
//         // Or use 8 times more amt
//         uint8 multiplier = 2;

//         uint256 lqtyAmount = 1e18;

//         uint256 powerInTheFuture = governance.lqtyToVotes(lqtyAmount, multiplier + 1, 1);
//         // Amt when delta is 1
//         // 0 when delta is 0
//         uint256 powerFromMoreDeposits =
//             governance.lqtyToVotes(lqtyAmount * multiplier, uint32(block.timestamp + 1), uint32(block.timestamp));

//         assertEq(powerInTheFuture, powerFromMoreDeposits, "Same result");
//     }

//     function test_math_soundness_fuzz(uint32 multiplier) public view {
//         vm.assume(multiplier < type(uint32).max - 1);
//         uint256 lqtyAmount = 1e10;

//         uint256 powerInTheFuture = governance.lqtyToVotes(lqtyAmount, multiplier + 1, 1);

//         // Amt when delta is 1
//         // 0 when delta is 0
//         uint256 powerFromMoreDeposits =
//             governance.lqtyToVotes(lqtyAmount * multiplier, uint32(block.timestamp + 1), uint32(block.timestamp));

//         assertEq(powerInTheFuture, powerFromMoreDeposits, "Same result");
//     }

//     // This test prepares for comparing votes and vetos for state
//     // forge test --match-test test_we_can_compare_votes_and_vetos -vv
//     // function test_we_can_compare_votes_and_vetos() public {
//     /// TODO AUDIT Known bug with rounding math
//     //     uint32 current_time = 123123123;
//     //     vm.warp(current_time);
//     //     // State at X
//     //     // State made of X and Y
//     //     uint32 time = current_time - 124;
//     //     uint256 votes = 124;
//     //     uint256 power = governance.lqtyToVotes(votes, current_time, time);

//     //     assertEq(power, (_averageAge(current_time, time)) * votes, "simple product");

//     //     // if it's a simple product we have the properties of multiplication, we can get back the value by dividing the tiem
//     //     uint256 resultingVotes = uint256(power / _averageAge(current_time, time));

//     //     assertEq(resultingVotes, votes, "We can get it back");

//     //     // If we can get it back, then we can also perform other operations like addition and subtraction
//     //     // Easy when same TS

//     //     // // But how do we sum stuff with different TS?
//     //     // // We need to sum the total and sum the % of average ts
//     //     uint256 votes_2 = 15;
//     //     uint32 time_2 = current_time - 15;

//     //     uint256 power_2 = governance.lqtyToVotes(votes_2, current_time, time_2);

//     //     uint256 total_power = power + power_2;

//     //     assertLe(total_power, uint256(type(uint256).max), "LT");

//     //     uint256 total_liquity = votes + votes_2;

//     //     uint32 avgTs = _calculateAverageTimestamp(time, time_2, votes, total_liquity);

//     //     console.log("votes", votes);
//     //     console.log("time", current_time - time);
//     //     console.log("power", power);

//     //     console.log("votes_2", votes_2);
//     //     console.log("time_2", current_time - time_2);
//     //     console.log("power_2", power_2);

//     //     uint256 total_power_from_avg = governance.lqtyToVotes(total_liquity, current_time, avgTs);

//     //     console.log("total_liquity", total_liquity);
//     //     console.log("avgTs", current_time - avgTs);
//     //     console.log("total_power_from_avg", total_power_from_avg);

//     //     // Now remove the same math so we show that the rounding can be weaponized, let's see

//     //     // WTF

//     //     // Prev, new, prev new
//     //     // AVG TS is the prev outer
//     //     // New Inner is time
//     //     uint32 attacked_avg_ts = _calculateAverageTimestamp(
//     //         avgTs,
//     //         time_2, // User removes their time
//     //         total_liquity,
//     //         votes // Votes = total_liquity - Vote_2
//     //     );

//     //     // NOTE: != time due to rounding error
//     //     console.log("attacked_avg_ts", current_time - attacked_avg_ts);

//     //     // BASIC VOTING TEST
//     //     // AFTER VOTING POWER IS X
//     //     // AFTER REMOVING VOTING IS 0

//     //     // Add a middle of random shit
//     //     // Show that the math remains sound

//     //     // Off by 40 BPS????? WAYY TOO MUCH | SOMETHING IS WRONG

//     //     // It doesn't sum up exactly becasue of rounding errors
//     //     // But we need the rounding error to be in favour of the protocol
//     //     // And currently they are not
//     //     assertEq(total_power, total_power_from_avg, "Sums up");

//     //     // From those we can find the average timestamp
//     //     uint256 resultingReturnedVotes = uint256(total_power_from_avg / _averageAge(current_time, time));
//     //     assertEq(resultingReturnedVotes, total_liquity, "Lqty matches");
//     // }

//     // forge test --match-test test_crit_user_can_dilute_total_votes -vv
//     // TODO: convert to an offset-based test
//     // function test_crit_user_can_dilute_total_votes() public {
//     //     // User A deposits normaly
//     //     vm.startPrank(user);

//     //     _stakeLQTY(user, 124);

//     //     vm.warp(block.timestamp + 124 - 15);

//     //     vm.startPrank(user2);
//     //     _stakeLQTY(user2, 15);

//     //     vm.warp(block.timestamp + 15);

//     //     vm.startPrank(user);
//     //     _allocate(address(baseInitiative1), 124, 0);
//     //     uint256 user1_avg = _getAverageTS(baseInitiative1);

//         // vm.startPrank(user2);
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));

//     //     uint256 griefed_avg = _getAverageTS(baseInitiative1);

//     //     uint256 vote_power_1 = governance.lqtyToVotes(124, uint32(block.timestamp), uint32(user1_avg));
//     //     uint256 vote_power_2 = governance.lqtyToVotes(124, uint32(block.timestamp), uint32(griefed_avg));

//     //     console.log("vote_power_1", vote_power_1);
//     //     console.log("vote_power_2", vote_power_2);

//     //     // assertEq(user1_avg, griefed_avg, "same avg"); // BREAKS, OFF BY ONE

//     //     // Causes a loss of power of 1 second per time this is done

//         // vm.startPrank(user);
//         // _reset(address(baseInitiative1));

//     //     uint256 final_avg = _getAverageTS(baseInitiative1);
//     //     console.log("final_avg", final_avg);

//     //     // This is not an issue, except for bribes, bribes can get the last claimer DOSS
//     // }

//     // forge test --match-test test_can_we_spam_to_revert -vv
//     // function test_can_we_spam_to_revert() public {
//     //     // User A deposits normaly
//     //     vm.startPrank(user);

//     //     _stakeLQTY(user, 124);

//     //     vm.warp(block.timestamp + 124);

//     //     vm.startPrank(user2);
//     //     _stakeLQTY(user2, 15);

//     //     vm.startPrank(user);
//     //     _allocate(address(baseInitiative1), 124, 0);

//         // vm.startPrank(user2);
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));

//     //     uint256 griefed_avg = _getAverageTS(baseInitiative1);
//     //     console.log("griefed_avg", griefed_avg);
//     //     console.log("block.timestamp", block.timestamp);

//     //     console.log("0?");

//     //     uint256 currentMagnifiedTs = uint256(block.timestamp) * uint256(1e26);

//         // vm.startPrank(user2);
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));

//     //     uint256 ts = _getAverageTS(baseInitiative1);
//     //     uint256 delta = currentMagnifiedTs - ts;
//     //     console.log("griefed_avg", ts);
//     //     console.log("delta", delta);
//     //     console.log("currentMagnifiedTs", currentMagnifiedTs);

//         // console.log("0?");
//         // uint256 i;
//         // while (i++ < 122) {
//         //     console.log("i", i);
//         //     _allocate(address(baseInitiative1), 15, 0);
//         //     _reset(address(baseInitiative1));
//         // }

//     //     console.log("1?");

//     //     ts = _getAverageTS(baseInitiative1);
//     //     delta = currentMagnifiedTs - ts;
//     //     console.log("griefed_avg", ts);
//     //     console.log("delta", delta);
//     //     console.log("currentMagnifiedTs", currentMagnifiedTs);

//         // // One more time
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));
//         // _allocate(address(baseInitiative1), 15, 0);
//         // _reset(address(baseInitiative1));
//         // _allocate(address(baseInitiative1), 15, 0);

//     //     /// NOTE: Keep 1 wei to keep rounding error
//     //     _allocate(address(baseInitiative1), 1, 0);

//     //     ts = _getAverageTS(baseInitiative1);
//     //     console.log("griefed_avg", ts);

//     //     vm.startPrank(user);
//     //     _reset(address(baseInitiative1));
//     //     _allocate(address(baseInitiative1), 124, 0);

//     //     ts = _getAverageTS(baseInitiative1);
//     //     console.log("end_ts", ts);
//     // }

//     // forge test --match-test test_basic_reset_flow -vv
//     function test_basic_reset_flow() public {
//         vm.startPrank(user);
//         // =========== epoch 1 ==================
//         // 1. user stakes lqty
//         int256 lqtyAmount = 2e18;
//         _stakeLQTY(user, uint256(lqtyAmount / 2));

//         // user allocates to baseInitiative1
//         _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
//         (,,uint256 allocatedLQTY,) = governance.userStates(user);
//         assertEq(allocatedLQTY, uint256(lqtyAmount / 2), "half");

//         _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
//         assertEq(allocatedLQTY, uint256(lqtyAmount / 2), "still half, the math is absolute now");
//     }

//     // forge test --match-test test_cutoff_logic -vv
//     function test_cutoff_logic() public {
//         vm.startPrank(user);
//         // =========== epoch 1 ==================
//         // 1. user stakes lqty
//         int256 lqtyAmount = 2e18;
//         _stakeLQTY(user, uint256(lqtyAmount));

//         // user allocates to baseInitiative1
//         _allocate(address(baseInitiative1), lqtyAmount / 2, 0); // 50% to it
//         (,,uint256 allocatedLQTY,) = governance.userStates(user);
//         assertEq(allocatedLQTY, uint256(lqtyAmount / 2), "Half");

//         // Go to Cutoff
//         // See that you can reduce
//         // See that you can Veto as much as you want
//         vm.warp(block.timestamp + (EPOCH_DURATION) - governance.EPOCH_VOTING_CUTOFF() + 1); // warp to end of second epoch before the voting cutoff

//         // Go to end of epoch, lazy math
//         while (!(governance.secondsWithinEpoch() > governance.EPOCH_VOTING_CUTOFF())) {
//             vm.warp(block.timestamp + 6 hours);
//         }
//         assertTrue(
//             governance.secondsWithinEpoch() > governance.EPOCH_VOTING_CUTOFF(), "We should not be able to vote more"
//         );

//         // Should fail to allocate more
//         _tryAllocate(address(baseInitiative1), lqtyAmount, 0, "Cannot increase");

//         // Can allocate less
//         _allocate(address(baseInitiative1), lqtyAmount / 2 - 1, 0);

//         // Can Veto more than allocate
//         _allocate(address(baseInitiative1), 0, lqtyAmount);
//     }

//     // Check if Flashloan can be used to cause issues?
//     // A flashloan would cause issues in the measure in which it breaks any specific property
//     // Or expectation

//     // Remove votes
//     // Removing votes would force you to exclusively remove
//     // You can always remove at any time afacit
//     // Removing just updates that + the weights
//     // The weights are the avg time * the number

//     function _getInitiativeOffset(address initiative) internal view returns (uint256) {
//         (,uint256 voteOffset,,,) = governance.initiativeStates(initiative);

//         return voteOffset;
//     }

//     function _stakeLQTY(address _user, uint256 amount) internal {
//         address userProxy = governance.deriveUserProxyAddress(_user);
//         lqty.approve(address(userProxy), amount);

//         governance.depositLQTY(amount);
//     }

//     // Helper function to get the current prank address
//     function currentUser() external view returns (address) {
//         return msg.sender;
//     }

//     function _prepareAllocateParams(address initiative, int256 votes, int256 vetos)
//         internal
//         view
//         returns (
//             address[] memory initiativesToReset,
//             address[] memory initiatives,
//             int256[] memory absoluteLQTYVotes,
//             int256[] memory absoluteLQTYVetos
//         )
//     {
//         (uint256 currentVote, uint256 currentVeto,) =
//             governance.lqtyAllocatedByUserToInitiative(this.currentUser(), address(initiative));
//         if (currentVote != 0 || currentVeto != 0) {
//             initiativesToReset = new address[](1);
//             initiativesToReset[0] = address(initiative);
//         }

//         initiatives = new address[](1);
//         initiatives[0] = initiative;
//         absoluteLQTYVotes = new int256[](1);
//         absoluteLQTYVotes[0] = votes;
//         absoluteLQTYVetos = new int256[](1);
//         absoluteLQTYVetos[0] = vetos;
//     }

//     function _allocate(address initiative, int256 votes, int256 vetos) internal {
//         (
//             address[] memory initiativesToReset,
//             address[] memory initiatives,
//             int256[] memory absoluteLQTYVotes,
//             int256[] memory absoluteLQTYVetos
//         ) = _prepareAllocateParams(initiative, votes, vetos);

//         governance.allocateLQTY(initiativesToReset, initiatives, absoluteLQTYVotes, absoluteLQTYVetos);
//     }

//     function _tryAllocate(address initiative, int256 votes, int256 vetos, bytes memory expectedError) internal {
//         (
//             address[] memory initiativesToReset,
//             address[] memory initiatives,
//             int256[] memory absoluteLQTYVotes,
//             int256[] memory absoluteLQTYVetos
//         ) = _prepareAllocateParams(initiative, votes, vetos);

//         vm.expectRevert(expectedError);
//         governance.allocateLQTY(initiativesToReset, initiatives, absoluteLQTYVotes, absoluteLQTYVetos);
//     }

//     function _reset(address initiative) internal {
//         address[] memory initiativesToReset = new address[](1);
//         initiativesToReset[0] = initiative;
//         governance.resetAllocations(initiativesToReset, true);
//     }
// }

// contract MockedVotingPowerTest is VotingPowerTest, MockStakingV1Deployer {
//     function setUp() public override {
//         (MockStakingV1 mockStakingV1, MockERC20Tester mockLQTY, MockERC20Tester mockLUSD) = deployMockStakingV1();
//         mockLQTY.mint(user, 2e18);
//         mockLQTY.mint(user2, 15);

//         lqty = mockLQTY;
//         lusd = mockLUSD;
//         stakingV1 = mockStakingV1;

//         super.setUp();
//     }
// }

// contract ForkedVotingPowerTest is VotingPowerTest {
//     function setUp() public override {
//         vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

//         lqty = IERC20(MAINNET_LQTY);
//         lusd = IERC20(MAINNET_LUSD);
//         stakingV1 = ILQTYStaking(MAINNET_LQTY_STAKING);

//         super.setUp();
//     }
// }
