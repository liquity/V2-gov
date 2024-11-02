// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {MockStakingV1} from "test/mocks/MockStakingV1.sol";
import {vm} from "@chimera/Hevm.sol";
import {IUserProxy} from "src/interfaces/IUserProxy.sol";
import {GovernanceProperties} from "./GovernanceProperties.sol";

// NOTE: These run only if you use `optimization` mode and set the correct prefix
// See echidna.yaml
abstract contract OptimizationProperties is GovernanceProperties {

    function optimize_max_sum_of_user_voting_weights_insolvent() public returns (int256) {
        VotesSumAndInitiativeSum[] memory results = _getUserVotesSumAndInitiativesVotes();

        int256 max = 0;

        // User have more than initiative, we are insolvent
        for(uint256 i; i < results.length; i++) {
            if(results[i].userSum > results[i].initiativeWeight) {
                max = int256(results[i].userSum) - int256(results[i].initiativeWeight);
            }
        }

        return max;
    }

    function optimize_max_sum_of_user_voting_weights_underpaying() public returns (int256) {
        VotesSumAndInitiativeSum[] memory results = _getUserVotesSumAndInitiativesVotes();

        int256 max = 0;

        for(uint256 i; i < results.length; i++) {
            // Initiative has more than users, we are underpaying
            if(results[i].initiativeWeight > results[i].userSum) {
                max = int256(results[i].initiativeWeight) - int256(results[i].userSum);
            }
        }

        return max;
    }

    function optimize_max_claim_insolvent() public returns (int256) {
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            // NOTE: Non view so it accrues state
            (Governance.InitiativeStatus status,, uint256 claimableAmount) = governance.getInitiativeState(deployedInitiatives[i]);

            claimableSum += claimableAmount;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        int256 max;
        if(claimableSum > boldAccrued) {
            max = int256(claimableSum) - int256(boldAccrued);
        }

        return max;
    }
    function optimize_max_claim_underpay() public returns (int256) {
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            // NOTE: Non view so it accrues state
            (Governance.InitiativeStatus status,, uint256 claimableAmount) = governance.getInitiativeState(deployedInitiatives[i]);

            claimableSum += claimableAmount;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        int256 max;
        if(boldAccrued > claimableSum) {
            max = int256(boldAccrued) - int256(claimableSum);
        }

        return max;
    }
    

    function optimize_property_sum_of_lqty_global_user_matches_insolvency() public returns (int256) {

        int256 max = 0;

        (uint256 totalUserCountedLQTY, uint256 totalCountedLQTY) = _getGlobalLQTYAndUserSum();

        if(totalUserCountedLQTY > totalCountedLQTY) {
            max = int256(totalUserCountedLQTY) - int256(totalCountedLQTY);
        }

        return max;
    }
    function optimize_property_sum_of_lqty_global_user_matches_underpaying() public returns (int256) {

        int256 max = 0;

        (uint256 totalUserCountedLQTY, uint256 totalCountedLQTY) = _getGlobalLQTYAndUserSum();

        if(totalCountedLQTY > totalUserCountedLQTY) {
            max = int256(totalCountedLQTY) - int256(totalUserCountedLQTY);
        }

        return max;
    }

    function optimize_property_sum_of_initatives_matches_total_votes_insolvency() public returns (int256) {

        int256 max = 0;

        (uint256 sumVotes, uint256 totalVotes) = _getInitiativesSnapshotsAndGlobalState();

        if(sumVotes > totalVotes) {
            max = int256(sumVotes) - int256(totalVotes);
        }

        return max;
    }
    function optimize_property_sum_of_initatives_matches_total_votes_underpaying() public returns (int256) {

        int256 max = 0;

        (uint256 sumVotes, uint256 totalVotes) = _getInitiativesSnapshotsAndGlobalState();

        if(totalVotes > sumVotes) {
            max = int256(totalVotes) - int256(sumVotes);
        }

        return max;
    }


}
    