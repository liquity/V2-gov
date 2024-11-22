// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {MockStakingV1} from "test/mocks/MockStakingV1.sol";
import {vm} from "@chimera/Hevm.sol";
import {IUserProxy} from "src/interfaces/IUserProxy.sol";

abstract contract GovernanceProperties is BeforeAfter {
    uint256 constant TOLLERANCE = 1e19; // NOTE: 1e18 is 1 second due to upscaling
    /// So we accept at most 10 seconds of errors

    /// A Initiative cannot change in status
    /// Except for being unregistered
    ///     Or claiming rewards
    function property_GV01() public {
        // first check that epoch hasn't changed after the operation
        if (_before.epoch == _after.epoch) {
            // loop through the initiatives and check that their status hasn't changed
            for (uint8 i; i < deployedInitiatives.length; i++) {
                address initiative = deployedInitiatives[i];

                // Hardcoded Allowed FSM
                if (_before.initiativeStatus[initiative] == Governance.InitiativeStatus.UNREGISTERABLE) {
                    // ALLOW TO SET DISABLE
                    if (_after.initiativeStatus[initiative] == Governance.InitiativeStatus.DISABLED) {
                        return;
                    }
                }

                if (_before.initiativeStatus[initiative] == Governance.InitiativeStatus.CLAIMABLE) {
                    // ALLOW TO CLAIM
                    if (_after.initiativeStatus[initiative] == Governance.InitiativeStatus.CLAIMED) {
                        return;
                    }
                }

                if (_before.initiativeStatus[initiative] == Governance.InitiativeStatus.NONEXISTENT) {
                    // Registered -> SKIP is ok
                    if (_after.initiativeStatus[initiative] == Governance.InitiativeStatus.WARM_UP) {
                        return;
                    }
                }

                eq(
                    uint256(_before.initiativeStatus[initiative]),
                    uint256(_after.initiativeStatus[initiative]),
                    "GV-01: Initiative state should only return one state per epoch"
                );
            }
        }
    }

    function property_GV_09() public {
        // User stakes
        // User allocated

        // allocated is always <= stakes
        for (uint256 i; i < users.length; i++) {
            // Only sum up user votes
            address userProxyAddress = governance.deriveUserProxyAddress(users[i]);
            uint256 stake = MockStakingV1(stakingV1).stakes(userProxyAddress);

            (uint88 user_allocatedLQTY,) = governance.userStates(users[i]);
            lte(user_allocatedLQTY, stake, "User can never allocated more than stake");
        }
    }

    // View vs non view must have same results
    function property_viewTotalVotesAndStateEquivalency() public {
        for (uint8 i; i < deployedInitiatives.length; i++) {
            (IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot_view,,) =
                governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);
            (, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot) =
                governance.snapshotVotesForInitiative(deployedInitiatives[i]);

            eq(initiativeSnapshot_view.votes, initiativeVoteSnapshot.votes, "votes");
            eq(initiativeSnapshot_view.forEpoch, initiativeVoteSnapshot.forEpoch, "forEpoch");
            eq(initiativeSnapshot_view.lastCountedEpoch, initiativeVoteSnapshot.lastCountedEpoch, "lastCountedEpoch");
            eq(initiativeSnapshot_view.vetos, initiativeVoteSnapshot.vetos, "vetos");
        }
    }

    function property_viewCalculateVotingThreshold() public {
        (,, bool shouldUpdate) = governance.getTotalVotesAndState();

        if (!shouldUpdate) {
            // If it's already synched it must match
            uint256 latestKnownThreshold = governance.getLatestVotingThreshold();
            uint256 calculated = governance.calculateVotingThreshold();
            eq(latestKnownThreshold, calculated, "match");
        }
    }

    // Function sound total math

    // NOTE: Global vs Uer vs Initiative requires changes
    // User is tracking votes and vetos together
    // Whereas Votes and Initiatives only track Votes
    /// The Sum of LQTY allocated by Users matches the global state
    // NOTE: Sum of positive votes
    // Remove the initiative from Unregistered Initiatives
    function property_sum_of_lqty_global_user_matches() public {
        // Get state
        // Get all users
        // Sum up all voted users
        // Total must match
        (uint256 totalUserCountedLQTY, uint256 totalCountedLQTY) = _getGlobalLQTYAndUserSum();

        eq(totalUserCountedLQTY, totalCountedLQTY, "Global vs SUM(Users_lqty) must match");
    }

    function _getGlobalLQTYAndUserSum() internal returns (uint256, uint256) {
        (
            uint88 totalCountedLQTY,
            // uint32 after_user_countedVoteLQTYAverageTimestamp // TODO: How do we do this?
        ) = governance.globalState();

        uint256 totalUserCountedLQTY;
        for (uint256 i; i < users.length; i++) {
            // Only sum up user votes
            (uint88 user_voteLQTY,) = _getAllUserAllocations(users[i], true);
            totalUserCountedLQTY += user_voteLQTY;
        }

        return (totalUserCountedLQTY, totalCountedLQTY);
    }

    // NOTE: In principle this will work since this is a easier to reach property vs checking each initiative
    function property_ensure_user_alloc_cannot_dos() public {
        for (uint256 i; i < users.length; i++) {
            // Only sum up user votes
            (uint88 user_voteLQTY,) = _getAllUserAllocations(users[i], false);

            lte(user_voteLQTY, uint88(type(int88).max), "User can never allocate more than int88");
        }
    }

    /// The Sum of LQTY allocated to Initiatives matches the Sum of LQTY allocated by users
    function property_sum_of_lqty_initiative_user_matches() public {
        // Get Initiatives
        // Get all users
        // Sum up all voted users & initiatives
        // Total must match
        uint256 totalInitiativesCountedVoteLQTY;
        uint256 totalInitiativesCountedVetoLQTY;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (uint88 voteLQTY, uint88 vetoLQTY,,,) = governance.initiativeStates(deployedInitiatives[i]);
            totalInitiativesCountedVoteLQTY += voteLQTY;
            totalInitiativesCountedVetoLQTY += vetoLQTY;
        }

        uint256 totalUserCountedLQTY;
        for (uint256 i; i < users.length; i++) {
            (uint88 user_allocatedLQTY,) = governance.userStates(users[i]);
            totalUserCountedLQTY += user_allocatedLQTY;
        }

        eq(
            totalInitiativesCountedVoteLQTY + totalInitiativesCountedVetoLQTY,
            totalUserCountedLQTY,
            "SUM(Initiatives_lqty) vs SUM(Users_lqty) must match"
        );
    }

    // TODO: also `lqtyAllocatedByUserToInitiative`
    // For each user, for each initiative, allocation is correct
    function property_sum_of_user_initiative_allocations() public {
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (uint88 initiative_voteLQTY, uint88 initiative_vetoLQTY,,,) =
                governance.initiativeStates(deployedInitiatives[i]);

            // Grab all users and sum up their participations
            uint256 totalUserVotes;
            uint256 totalUserVetos;
            for (uint256 j; j < users.length; j++) {
                (uint88 vote_allocated, uint88 veto_allocated) = _getUserAllocation(users[j], deployedInitiatives[i]);
                totalUserVotes += vote_allocated;
                totalUserVetos += veto_allocated;
            }

            eq(initiative_voteLQTY, totalUserVotes, "Sum of users, matches initiative votes");
            eq(initiative_vetoLQTY, totalUserVetos, "Sum of users, matches initiative vetos");
        }
    }

    // sum of voting power for users that allocated to an initiative == the voting power of the initiative
    /// TODO ??
    function property_sum_of_user_voting_weights_strict() public {
        // loop through all users
        // - calculate user voting weight for the given timestamp
        // - sum user voting weights for the given epoch
        // - compare with the voting weight of the initiative for the epoch for the same timestamp
        VotesSumAndInitiativeSum[] memory votesSumAndInitiativeValues = _getUserVotesSumAndInitiativesVotes();

        for (uint256 i; i < votesSumAndInitiativeValues.length; i++) {
            eq(
                votesSumAndInitiativeValues[i].userSum,
                votesSumAndInitiativeValues[i].initiativeWeight,
                "initiative voting weights and user's allocated weight differs for initiative"
            );
        }
    }

    function property_sum_of_user_voting_weights_bounded() public {
        // loop through all users
        // - calculate user voting weight for the given timestamp
        // - sum user voting weights for the given epoch
        // - compare with the voting weight of the initiative for the epoch for the same timestamp
        VotesSumAndInitiativeSum[] memory votesSumAndInitiativeValues = _getUserVotesSumAndInitiativesVotes();

        for (uint256 i; i < votesSumAndInitiativeValues.length; i++) {
            eq(votesSumAndInitiativeValues[i].userSum, votesSumAndInitiativeValues[i].initiativeWeight, "Matching");
            t(
                votesSumAndInitiativeValues[i].userSum == votesSumAndInitiativeValues[i].initiativeWeight
                    || (
                        votesSumAndInitiativeValues[i].userSum
                            >= votesSumAndInitiativeValues[i].initiativeWeight - TOLLERANCE
                            && votesSumAndInitiativeValues[i].userSum
                                <= votesSumAndInitiativeValues[i].initiativeWeight + TOLLERANCE
                    ),
                "initiative voting weights and user's allocated weight match within tollerance"
            );
        }
    }

    struct VotesSumAndInitiativeSum {
        uint256 userSum;
        uint256 initiativeWeight;
    }

    function _getUserVotesSumAndInitiativesVotes() internal returns (VotesSumAndInitiativeSum[] memory) {
        VotesSumAndInitiativeSum[] memory acc = new VotesSumAndInitiativeSum[](deployedInitiatives.length);
        for (uint256 i; i < deployedInitiatives.length; i++) {
            uint240 userWeightAccumulatorForInitiative;
            for (uint256 j; j < users.length; j++) {
                (uint88 userVoteLQTY,,) = governance.lqtyAllocatedByUserToInitiative(users[j], deployedInitiatives[i]);
                // TODO: double check that okay to use this average timestamp
                (, uint120 averageStakingTimestamp) = governance.userStates(users[j]);
                // add the weight calculated for each user's allocation to the accumulator
                userWeightAccumulatorForInitiative += governance.lqtyToVotes(
                    userVoteLQTY, uint120(block.timestamp) * uint120(1e18), averageStakingTimestamp
                );
            }

            (uint88 initiativeVoteLQTY,, uint120 initiativeAverageStakingTimestampVoteLQTY,,) =
                governance.initiativeStates(deployedInitiatives[i]);
            uint240 initiativeWeight = governance.lqtyToVotes(
                initiativeVoteLQTY, uint120(block.timestamp) * uint120(1e18), initiativeAverageStakingTimestampVoteLQTY
            );

            acc[i].userSum = userWeightAccumulatorForInitiative;
            acc[i].initiativeWeight = initiativeWeight;
        }

        return acc;
    }

    function property_allocations_are_never_dangerously_high() public {
        for (uint256 i; i < deployedInitiatives.length; i++) {
            for (uint256 j; j < users.length; j++) {
                (uint88 vote_allocated, uint88 veto_allocated) = _getUserAllocation(users[j], deployedInitiatives[i]);
                lte(vote_allocated, uint88(type(int88).max), "Vote is never above int88.max");
                lte(veto_allocated, uint88(type(int88).max), "Veto is Never above int88.max");
            }
        }
    }

    function property_sum_of_initatives_matches_total_votes_strict() public {
        // Sum up all initiatives
        // Compare to total votes
        (uint256 allocatedLQTYSum, uint256 totalCountedLQTY, uint256 votedPowerSum, uint256 govPower) =
            _getInitiativeStateAndGlobalState();

        eq(allocatedLQTYSum, totalCountedLQTY, "LQTY Sum of Initiative State matches Global State at all times");
        eq(votedPowerSum, govPower, "Voting Power Sum of Initiative State matches Global State at all times");
    }

    function property_sum_of_initatives_matches_total_votes_bounded() public {
        // Sum up all initiatives
        // Compare to total votes
        (uint256 allocatedLQTYSum, uint256 totalCountedLQTY, uint256 votedPowerSum, uint256 govPower) =
            _getInitiativeStateAndGlobalState();

        t(
            allocatedLQTYSum == totalCountedLQTY
                || (allocatedLQTYSum >= totalCountedLQTY - TOLLERANCE && allocatedLQTYSum <= totalCountedLQTY + TOLLERANCE),
            "Sum of Initiative LQTY And State matches within absolute tollerance"
        );

        t(
            votedPowerSum == govPower
                || (votedPowerSum >= govPower - TOLLERANCE && votedPowerSum <= govPower + TOLLERANCE),
            "Sum of Initiative LQTY And State matches within absolute tollerance"
        );
    }

    function _getInitiativeStateAndGlobalState() internal returns (uint256, uint256, uint256, uint256) {
        (uint88 totalCountedLQTY, uint120 global_countedVoteLQTYAverageTimestamp) = governance.globalState();

        // Can sum via projection I guess

        // Global Acc
        // Initiative Acc
        uint256 allocatedLQTYSum;
        uint256 votedPowerSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (
                uint88 voteLQTY,
                uint88 vetoLQTY,
                uint120 averageStakingTimestampVoteLQTY,
                uint120 averageStakingTimestampVetoLQTY,
            ) = governance.initiativeStates(deployedInitiatives[i]);

            // Conditional, only if not DISABLED
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(deployedInitiatives[i]);
            // Conditionally add based on state
            if (status != Governance.InitiativeStatus.DISABLED) {
                allocatedLQTYSum += voteLQTY;
                // Sum via projection
                votedPowerSum += governance.lqtyToVotes(
                    voteLQTY,
                    uint120(block.timestamp) * uint120(governance.TIMESTAMP_PRECISION()),
                    averageStakingTimestampVoteLQTY
                );
            }
        }

        uint256 govPower = governance.lqtyToVotes(
            totalCountedLQTY,
            uint120(block.timestamp) * uint120(governance.TIMESTAMP_PRECISION()),
            global_countedVoteLQTYAverageTimestamp
        );

        return (allocatedLQTYSum, totalCountedLQTY, votedPowerSum, govPower);
    }

    /// NOTE: This property can break in some specific combinations of:
    /// Becomes SKIP due to high treshold
    /// threshold is lowered
    /// Initiative becomes claimable
    function check_skip_consistecy(uint8 initiativeIndex) public {
        // If a initiative has no votes
        // In the next epoch it can either be SKIP or UNREGISTERABLE
        address initiative = _getDeployedInitiative(initiativeIndex);

        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
        if (status == Governance.InitiativeStatus.SKIP) {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());
            (Governance.InitiativeStatus newStatus,,) = governance.getInitiativeState(initiative);
            t(
                uint256(status) == uint256(newStatus)
                    || uint256(newStatus) == uint256(Governance.InitiativeStatus.UNREGISTERABLE)
                    || uint256(newStatus) == uint256(Governance.InitiativeStatus.CLAIMABLE),
                "Either SKIP or UNREGISTERABLE or CLAIMABLE"
            );
        }
    }

    function check_warmup_unregisterable_consistency(uint8 initiativeIndex) public {
        // Status after MUST NOT be UNREGISTERABLE
        address initiative = _getDeployedInitiative(initiativeIndex);
        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);

        if (status == Governance.InitiativeStatus.WARM_UP) {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());
            (Governance.InitiativeStatus newStatus,,) = governance.getInitiativeState(initiative);

            // Next status must be SKIP, because by definition it has
            // Received no votes (cannot)
            // Must not be UNREGISTERABLE
            t(uint256(newStatus) == uint256(Governance.InitiativeStatus.SKIP), "Must be SKIP");
        }
    }

    /// NOTE: This property can break in some specific combinations of:
    /// Becomes unregisterable due to high treshold
    /// Is not unregistered
    /// threshold is lowered
    /// Initiative becomes claimable
    function check_unregisterable_consistecy(uint8 initiativeIndex) public {
        // If a initiative has no votes and is UNREGISTERABLE
        // In the next epoch it will remain UNREGISTERABLE
        address initiative = _getDeployedInitiative(initiativeIndex);

        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(initiative);
        if (status == Governance.InitiativeStatus.UNREGISTERABLE) {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());
            (Governance.InitiativeStatus newStatus,,) = governance.getInitiativeState(initiative);
            t(uint256(status) == uint256(newStatus), "UNREGISTERABLE must remain UNREGISTERABLE");
        }
    }

    // TODO: Maybe check snapshot of states and ensure it can never be less than 4 epochs b4 unregisterable

    function check_claim_soundness() public {
        // Check if initiative is claimable
        // If it is assert the check
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (Governance.InitiativeStatus status,,) = governance.getInitiativeState(deployedInitiatives[i]);

            (, Governance.InitiativeState memory initiativeState,) =
                governance.getInitiativeSnapshotAndState(deployedInitiatives[i]);

            if (status == Governance.InitiativeStatus.CLAIMABLE) {
                t(governance.epoch() > 0, "Can never be claimable in epoch 0!"); // Overflow Check, also flags misconfiguration
                // Normal check
                t(initiativeState.lastEpochClaim < governance.epoch() - 1, "Cannot be CLAIMABLE, should be CLAIMED");
            }
        }
    }

    // TODO: Optimization property to show max loss
    // TODO: Same identical optimization property for Bribes claiming
    /// Should prob change the math to view it in bribes for easier debug
    function check_claimable_solvency() public {
        // Accrue all initiatives
        // Get bold amount
        // Sum up the initiatives claimable vs the bold

        // Check if initiative is claimable
        // If it is assert the check
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            // NOTE: Non view so it accrues state
            (Governance.InitiativeStatus status,, uint256 claimableAmount) =
                governance.getInitiativeState(deployedInitiatives[i]);

            claimableSum += claimableAmount;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        lte(claimableSum, boldAccrued, "Total Claims are always LT all bold");
    }

    function check_realized_claiming_solvency() public {
        uint256 claimableSum;
        for (uint256 i; i < deployedInitiatives.length; i++) {
            uint256 claimed = governance.claimForInitiative(deployedInitiatives[i]);

            claimableSum += claimed;
        }

        // Grab accrued
        uint256 boldAccrued = governance.boldAccrued();

        lte(claimableSum, boldAccrued, "Total Claims are always LT all bold");
    }

    // TODO: Optimization of this to determine max damage, and max insolvency

    function _getUserAllocation(address theUser, address initiative)
        internal
        view
        returns (uint88 votes, uint88 vetos)
    {
        (votes, vetos,) = governance.lqtyAllocatedByUserToInitiative(theUser, initiative);
    }

    function _getAllUserAllocations(address theUser, bool skipDisabled) internal returns (uint88 votes, uint88 vetos) {
        for (uint256 i; i < deployedInitiatives.length; i++) {
            (uint88 allocVotes, uint88 allocVetos,) =
                governance.lqtyAllocatedByUserToInitiative(theUser, deployedInitiatives[i]);
            if (skipDisabled) {
                (Governance.InitiativeStatus status,,) = governance.getInitiativeState(deployedInitiatives[i]);

                // Conditionally add based on state
                if (status != Governance.InitiativeStatus.DISABLED) {
                    votes += allocVotes;
                    vetos += allocVetos;
                }
            } else {
                // Always add
                votes += allocVotes;
                vetos += allocVetos;
            }
        }
    }

    function property_alloc_deposit_reset_is_idempotent(
        uint8 initiativesIndex,
        uint96 deltaLQTYVotes,
        uint96 deltaLQTYVetos,
        uint88 lqtyAmount
    ) public withChecks {
        address targetInitiative = _getDeployedInitiative(initiativesIndex);

        // 0. Reset first to ensure we start fresh, else the totals can be out of whack
        // TODO: prob unnecessary
        // Cause we always reset anyway
        {
            int88[] memory zeroes = new int88[](deployedInitiatives.length);

            governance.allocateLQTY(deployedInitiatives, deployedInitiatives, zeroes, zeroes);
        }

        // GET state and initiative data before allocation
        (uint88 totalCountedLQTY, uint120 user_countedVoteLQTYAverageTimestamp) = governance.globalState();
        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint120 averageStakingTimestampVoteLQTY,
            uint120 averageStakingTimestampVetoLQTY,
        ) = governance.initiativeStates(targetInitiative);

        // Allocate
        {
            uint96 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user)).staked();

            address[] memory initiatives = new address[](1);
            initiatives[0] = targetInitiative;
            int88[] memory deltaLQTYVotesArray = new int88[](1);
            deltaLQTYVotesArray[0] = int88(uint88(deltaLQTYVotes % stakedAmount));
            int88[] memory deltaLQTYVetosArray = new int88[](1);
            deltaLQTYVetosArray[0] = int88(uint88(deltaLQTYVetos % stakedAmount));

            governance.allocateLQTY(deployedInitiatives, initiatives, deltaLQTYVotesArray, deltaLQTYVetosArray);
        }

        // Deposit (Changes total LQTY an hopefully also changes ts)
        {
            (, uint120 averageStakingTimestamp1) = governance.userStates(user);

            lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user));
            governance.depositLQTY(lqtyAmount);
            (, uint120 averageStakingTimestamp2) = governance.userStates(user);

            require(averageStakingTimestamp2 > averageStakingTimestamp1, "Must have changed");
        }

        // REMOVE STUFF to remove the user data
        {
            int88[] memory zeroes = new int88[](deployedInitiatives.length);
            governance.allocateLQTY(deployedInitiatives, deployedInitiatives, zeroes, zeroes);
        }

        // Check total allocation and initiative allocation
        {
            (uint88 after_totalCountedLQTY, uint120 after_user_countedVoteLQTYAverageTimestamp) =
                governance.globalState();
            (
                uint88 after_voteLQTY,
                uint88 after_vetoLQTY,
                uint120 after_averageStakingTimestampVoteLQTY,
                uint120 after_averageStakingTimestampVetoLQTY,
            ) = governance.initiativeStates(targetInitiative);

            eq(voteLQTY, after_voteLQTY, "Same vote");
            eq(vetoLQTY, after_vetoLQTY, "Same veto");
            eq(averageStakingTimestampVoteLQTY, after_averageStakingTimestampVoteLQTY, "Same ts vote");
            eq(averageStakingTimestampVetoLQTY, after_averageStakingTimestampVetoLQTY, "Same ts veto");

            eq(totalCountedLQTY, after_totalCountedLQTY, "Same total LQTY");
            eq(user_countedVoteLQTYAverageTimestamp, after_user_countedVoteLQTYAverageTimestamp, "Same total ts");
        }
    }
}
