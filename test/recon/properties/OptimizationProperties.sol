// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {vm} from "@chimera/Hevm.sol";
import {IUserProxy} from "src/interfaces/IUserProxy.sol";
import {GovernanceProperties} from "./GovernanceProperties.sol";
import {console} from "forge-std/console.sol";

// NOTE: These run only if you use `optimization` mode and set the correct prefix
// See echidna.yaml
abstract contract OptimizationProperties is GovernanceProperties {
    function optimize_max_sum_of_user_voting_weights_insolvent() public returns (int256) {
        VotesSumAndInitiativeSum[] memory results = _getUserVotesSumAndInitiativesVotes();

        int256 max = 0;

        // User have more than initiative, we are insolvent
        for (uint256 i; i < results.length; i++) {
            if (results[i].userSum > results[i].initiativeWeight) {
                max = int256(results[i].userSum) - int256(results[i].initiativeWeight);
            }
        }

        return max;
    }

    function optimize_max_sum_of_user_voting_weights_underpaying() public returns (int256) {
        VotesSumAndInitiativeSum[] memory results = _getUserVotesSumAndInitiativesVotes();

        int256 max = 0;

        for (uint256 i; i < results.length; i++) {
            // Initiative has more than users, we are underpaying
            if (results[i].initiativeWeight > results[i].userSum) {
                max = int256(results[i].initiativeWeight) - int256(results[i].userSum);
            }
        }

        return max;
    }

    function optimize_max_claim_insolvent() public returns (int256) {
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            // NOTE: Non view so it accrues state
            (IGovernance.InitiativeStatus status,, uint256 claimableAmount) =
                governance.getInitiativeState(deployedInitiatives[i]);

            claimableSum += claimableAmount;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        int256 max;
        if (claimableSum > boldAccrued) {
            max = int256(claimableSum) - int256(boldAccrued);
        }

        return max;
    }

    // NOTE: This property is not particularly good as you can just do a donation and not vote
    // This douesn't really highlight a loss
    function optimize_max_claim_underpay() public returns (int256) {
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            // NOTE: Non view so it accrues state
            (IGovernance.InitiativeStatus status,, uint256 claimableAmount) =
                governance.getInitiativeState(deployedInitiatives[i]);

            claimableSum += claimableAmount;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        int256 max;
        if (boldAccrued > claimableSum) {
            max = int256(boldAccrued) - int256(claimableSum);
        }

        return max;
    }

    function property_sum_of_initatives_matches_total_votes_insolvency_assertion() public {
        uint256 delta = 0;

        (,, uint256 votedPowerSum, uint256 govPower) = _getInitiativeStateAndGlobalState();

        if (votedPowerSum > govPower) {
            delta = votedPowerSum - govPower;

            console.log("votedPowerSum * 1e18 / govPower", votedPowerSum * 1e18 / govPower);
        }

        console.log("votedPowerSum", votedPowerSum);
        console.log("govPower", govPower);
        console.log("delta", delta);

        t(delta < 4e25, "Delta is too big"); // 3e25 was found via optimization, no value past that was found
    }

    function optimize_property_sum_of_lqty_global_user_matches_insolvency() public returns (int256) {
        int256 max = 0;

        (uint256 totalUserCountedLQTY, uint256 totalCountedLQTY) = _getGlobalLQTYAndUserSum();

        if (totalUserCountedLQTY > totalCountedLQTY) {
            max = int256(totalUserCountedLQTY) - int256(totalCountedLQTY);
        }

        return max;
    }

    function optimize_property_sum_of_lqty_global_user_matches_underpaying() public returns (int256) {
        int256 max = 0;

        (uint256 totalUserCountedLQTY, uint256 totalCountedLQTY) = _getGlobalLQTYAndUserSum();

        if (totalCountedLQTY > totalUserCountedLQTY) {
            max = int256(totalCountedLQTY) - int256(totalUserCountedLQTY);
        }

        return max;
    }

    function optimize_property_sum_of_initatives_matches_total_votes_insolvency() public returns (bool) {
        int256 max = 0;

        (,, uint256 votedPowerSum, uint256 govPower) = _getInitiativeStateAndGlobalState();

        if (votedPowerSum > govPower) {
            max = int256(votedPowerSum) - int256(govPower);
        }

        return max < 3e25;
    }

    function optimize_property_sum_of_initatives_matches_total_votes_underpaying() public returns (int256) {
        int256 max = 0;

        (,, uint256 votedPowerSum, uint256 govPower) = _getInitiativeStateAndGlobalState();

        if (govPower > votedPowerSum) {
            max = int256(govPower) - int256(votedPowerSum);
        }

        return max; // 177155848800000000000000000000000000 (2^117)
    }
}
