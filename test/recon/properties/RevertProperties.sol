// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";
import {Governance} from "src/Governance.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "src/interfaces/IBribeInitiative.sol";

// The are view functions that should never revert
abstract contract RevertProperties is BeforeAfter {

    function property_shouldNeverRevertSnapshotAndState(uint8 initiativeIndex) public {
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.getInitiativeSnapshotAndState(initiative) {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldGetTotalVotesAndState() public {
        try governance.getTotalVotesAndState() {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertepoch() public {
        try governance.epoch() {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertepochStart(uint8 initiativeIndex) public {
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.getInitiativeSnapshotAndState(initiative) {} catch {
            t(false, "should never revert");
        }
    }

    function property_shouldNeverRevertsecondsWithinEpoch() public {
        try governance.secondsWithinEpoch() {} catch {
            t(false, "should never revert");
        }
    }

    function property_shouldNeverRevertlqtyToVotes() public {
        // TODO GRAB THE STATE VALUES
        // governance.lqtyToVotes();
    }

    function property_shouldNeverRevertgetLatestVotingThreshold() public {
        try governance.getLatestVotingThreshold() {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertcalculateVotingThreshold() public {
        try governance.calculateVotingThreshold() {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertgetTotalVotesAndState() public {
        try governance.getTotalVotesAndState() {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertgetInitiativeSnapshotAndState(uint8 initiativeIndex) public {
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.getInitiativeSnapshotAndState(initiative) {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertsnapshotVotesForInitiative(uint8 initiativeIndex) public {
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.snapshotVotesForInitiative(initiative) {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertgetInitiativeState(uint8 initiativeIndex) public {
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.getInitiativeState(initiative) {} catch {
            t(false, "should never revert");
        }
    }
    function property_shouldNeverRevertgetInitiativeState_arbitrary(address initiative) public {
        try governance.getInitiativeState(initiative) {} catch {
            t(false, "should never revert");
        }
    }

    // TODO: Consider adding `getInitiativeState` with random params
    // Technically not real, but IMO we should make sure it's safe for all params

    function property_shouldNeverRevertgetInitiativeState_arbitrary(
        address _initiative,
        IGovernance.VoteSnapshot memory _votesSnapshot,
        IGovernance.InitiativeVoteSnapshot memory _votesForInitiativeSnapshot,
        IGovernance.InitiativeState memory _initiativeState
    ) public {
        // NOTE: Maybe this can revert due to specific max values
        try governance.getInitiativeState(
            _initiative,
            _votesSnapshot,
            _votesForInitiativeSnapshot,
            _initiativeState
        ) {} catch {
            t(false, "should never revert");
        }
    }
}