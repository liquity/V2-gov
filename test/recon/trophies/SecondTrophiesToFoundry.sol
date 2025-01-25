// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TargetFunctions} from "../TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {Governance} from "src/Governance.sol";

import {console} from "forge-std/console.sol";

contract SecondTrophiesToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-test test_property_sum_of_initatives_matches_total_votes_strict_2 -vv
    function test_property_sum_of_initatives_matches_total_votes_strict_2() public {
        governance_depositLQTY_2(2);

        vm.warp(block.timestamp + 434544);

        vm.roll(block.number + 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 171499);
        governance_allocateLQTY_clamped_single_initiative_2nd_user(0, 1, 0);

        helper_deployInitiative();

        governance_depositLQTY(2);

        vm.warp(block.timestamp + 322216);

        vm.roll(block.number + 1);

        governance_registerInitiative(1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 449572);
        governance_allocateLQTY_clamped_single_initiative(1, 75095343, 0);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 436994);
        property_sum_of_initatives_matches_total_votes_strict();
        // Of by 1
        // I think this should be off by a bit more than 1
        // But ultimately always less
    }

    // forge test --match-test test_property_sum_of_user_voting_weights_0 -vv
    function test_property_sum_of_user_voting_weights_0() public {
        vm.warp(block.timestamp + 365090);

        vm.roll(block.number + 1);

        governance_depositLQTY_2(3);

        vm.warp(block.timestamp + 164968);

        vm.roll(block.number + 1);

        governance_depositLQTY(2);

        vm.warp(block.timestamp + 74949);

        vm.roll(block.number + 1);

        governance_allocateLQTY_clamped_single_initiative_2nd_user(0, 2, 0);

        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);

        property_sum_of_user_voting_weights_bounded();

        /// Of by 2
    }

    // forge test --match-test test_property_sum_of_lqty_global_user_matches_3 -vv
    function test_property_sum_of_lqty_global_user_matches_3() public {
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 45381);
        governance_depositLQTY_2(161673733563);

        vm.roll(block.number + 92);
        vm.warp(block.timestamp + 156075);
        property_BI03();

        vm.roll(block.number + 305);
        vm.warp(block.timestamp + 124202);
        property_BI04();

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 296079);
        governance_allocateLQTY_clamped_single_initiative_2nd_user(0, 1, 0);

        vm.roll(block.number + 4);
        vm.warp(block.timestamp + 179667);
        helper_deployInitiative();

        governance_depositLQTY(2718660550802480907);

        vm.roll(block.number + 6);
        vm.warp(block.timestamp + 383590);
        property_BI07();

        vm.warp(block.timestamp + 246073);

        vm.roll(block.number + 79);

        vm.roll(block.number + 4);
        vm.warp(block.timestamp + 322216);
        governance_depositLQTY(1);

        vm.warp(block.timestamp + 472018);

        vm.roll(block.number + 215);

        governance_registerInitiative(1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 419805);
        governance_allocateLQTY_clamped_single_initiative(1, 3700338125821584341973, 0);

        vm.warp(block.timestamp + 379004);

        vm.roll(block.number + 112);

        governance_unregisterInitiative(0);

        property_sum_of_lqty_global_user_matches();
    }

    // forge test --match-test test_governance_claimForInitiativeDoesntRevert_5 -vv
    function test_governance_claimForInitiativeDoesntRevert_5() public {
        governance_depositLQTY_2(96505858);
        _loginitiative_and_state(); // 0

        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 191303);
        property_BI03();
        _loginitiative_and_state(); // 1

        vm.warp(block.timestamp + 100782);

        vm.roll(block.number + 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 344203);
        governance_allocateLQTY_clamped_single_initiative_2nd_user(0, 1, 0);
        _loginitiative_and_state(); // 2

        vm.warp(block.timestamp + 348184);

        vm.roll(block.number + 177);

        helper_deployInitiative();
        _loginitiative_and_state(); // 3

        helper_accrueBold(1000135831883853852074);
        _loginitiative_and_state(); // 4

        governance_depositLQTY(2293362807359);
        _loginitiative_and_state(); // 5

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 151689);
        property_BI04();
        _loginitiative_and_state(); // 6

        governance_registerInitiative(1);
        _loginitiative_and_state(); // 7
        property_sum_of_initatives_matches_total_votes_bounded();

        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 449572);
        governance_allocateLQTY_clamped_single_initiative(1, 330671315851182842292, 0);
        _loginitiative_and_state(); // 8
        property_sum_of_initatives_matches_total_votes_bounded();

        // governance_resetAllocations(); // user 1 has nothing to reset
        _loginitiative_and_state(); // In lack of reset, we have 2 wei error | With reset the math is off by 7x
        property_sum_of_initatives_matches_total_votes_bounded();
        console.log("time 0", block.timestamp);

        vm.warp(block.timestamp + 231771);
        vm.roll(block.number + 5);
        _loginitiative_and_state();
        console.log("time 0", block.timestamp);

        // Both of these are fine
        // Meaning all LQTY allocation is fine here
        // Same for user voting weights
        property_sum_of_user_voting_weights_bounded();
        property_sum_of_lqty_global_user_matches();

        property_sum_of_initatives_matches_total_votes_bounded();
        (IGovernance.VoteSnapshot memory snapshot,,) = governance.getTotalVotesAndState();

        uint256 initiativeVotesSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot,,) =
                governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);
            (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(deployedInitiatives[i]);

            // if (status != IGovernance.InitiativeStatus.DISABLED) {
            // FIX: Only count total if initiative is not disabled
            initiativeVotesSum += initiativeSnapshot.votes;
            // }
        }
        console.log("snapshot.votes", snapshot.votes);
        console.log("initiativeVotesSum", initiativeVotesSum);
        console.log("bold.balance", lusd.balanceOf(address(governance)));
        governance_claimForInitiativeDoesntRevert(0); // Because of the quickfix this will not revert anymore
    }

    uint256 loggerCount;

    function _loginitiative_and_state() internal {
        (IGovernance.VoteSnapshot memory snapshot, IGovernance.GlobalState memory state,) =
            governance.getTotalVotesAndState();
        console.log("");
        console.log("loggerCount", loggerCount++);
        console.log("snapshot.votes", snapshot.votes);

        console.log("state.countedVoteLQTY", state.countedVoteLQTY);

        for (uint256 i; i < deployedInitiatives.length; i++) {
            (
                IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot,
                IGovernance.InitiativeState memory initiativeState,
            ) = governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);

            console.log("initiativeState.voteLQTY", initiativeState.voteLQTY);

            assertEq(snapshot.forEpoch, initiativeSnapshot.forEpoch, "No desynch");
            console.log("initiativeSnapshot.votes", initiativeSnapshot.votes);
        }
    }

    function test_property_BI07_4() public {
        vm.warp(block.timestamp + 562841);

        vm.roll(block.number + 1);

        governance_depositLQTY_2(2);

        vm.warp(block.timestamp + 243877);

        vm.roll(block.number + 1);

        uint8 initiativesIndex = 0;
        governance_allocateLQTY_clamped_single_initiative_2nd_user(initiativesIndex, 1, 0);

        vm.warp(block.timestamp + 403427);

        vm.roll(block.number + 1);

        // SHIFTS the week
        // Doesn't check latest alloc for each user
        // Property is broken due to wrong spec
        // For each user you need to grab the latest via the Governance.allocatedByUser
        address[] memory initiativesToReset = new address[](1);
        initiativesToReset[0] = _getDeployedInitiative(initiativesIndex);
        vm.startPrank(user2);
        property_resetting_never_reverts(initiativesToReset);

        property_BI07();
    }

    // forge test --match-test test_property_sum_of_user_voting_weights_0 -vv
    function test_property_sum_of_user_voting_weights_1() public {
        vm.warp(block.timestamp + 365090);

        vm.roll(block.number + 1);

        governance_depositLQTY_2(3);

        vm.warp(block.timestamp + 164968);

        vm.roll(block.number + 1);

        governance_depositLQTY(2);

        vm.warp(block.timestamp + 74949);

        vm.roll(block.number + 1);

        governance_allocateLQTY_clamped_single_initiative_2nd_user(0, 2, 0);

        governance_allocateLQTY_clamped_single_initiative(0, 1, 0);

        property_sum_of_user_voting_weights_bounded();
    }
}
