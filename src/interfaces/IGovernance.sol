// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "./ILQTYStaking.sol";

import {PermitParams} from "../utils/Types.sol";

uint256 constant UNREGISTERED_INITIATIVE = type(uint256).max;

interface IGovernance {
    enum HookStatus {
        Failed,
        Succeeded,
        NotCalled
    }

    /// @notice Emitted when a user deposits LQTY
    /// @param user The account depositing LQTY
    /// @param rewardRecipient The account receiving the LUSD/ETH rewards earned from staking in V1, if claimed
    /// @param lqtyAmount The amount of LQTY being deposited
    /// @return lusdReceived Amount of LUSD tokens received as a side-effect of staking new LQTY
    /// @return lusdSent Amount of LUSD tokens sent to `rewardRecipient` (may include previously received LUSD)
    /// @return ethReceived Amount of ETH received as a side-effect of staking new LQTY
    /// @return ethSent Amount of ETH sent to `rewardRecipient` (may include previously received ETH)
    event DepositLQTY(
        address indexed user,
        address rewardRecipient,
        uint256 lqtyAmount,
        uint256 lusdReceived,
        uint256 lusdSent,
        uint256 ethReceived,
        uint256 ethSent
    );

    /// @notice Emitted when a user withdraws LQTY or claims V1 staking rewards
    /// @param user The account withdrawing LQTY or claiming V1 staking rewards
    /// @param recipient The account receiving the LQTY withdrawn, and if claimed, the LUSD/ETH rewards earned from staking in V1
    /// @return lqtyReceived Amount of LQTY tokens actually withdrawn (may be lower than the `_lqtyAmount` passed to `withdrawLQTY`)
    /// @return lqtySent Amount of LQTY tokens sent to `recipient` (may include LQTY sent to the user's proxy from sources other than V1 staking)
    /// @return lusdReceived Amount of LUSD tokens received as a side-effect of staking new LQTY
    /// @return lusdSent Amount of LUSD tokens sent to `recipient` (may include previously received LUSD)
    /// @return ethReceived Amount of ETH received as a side-effect of staking new LQTY
    /// @return ethSent Amount of ETH sent to `recipient` (may include previously received ETH)
    event WithdrawLQTY(
        address indexed user,
        address recipient,
        uint256 lqtyReceived,
        uint256 lqtySent,
        uint256 lusdReceived,
        uint256 lusdSent,
        uint256 ethReceived,
        uint256 ethSent
    );

    event SnapshotVotes(uint256 votes, uint256 forEpoch, uint256 boldAccrued);
    event SnapshotVotesForInitiative(address indexed initiative, uint256 votes, uint256 vetos, uint256 forEpoch);

    event RegisterInitiative(address initiative, address registrant, uint256 atEpoch, HookStatus hookStatus);
    event UnregisterInitiative(address initiative, uint256 atEpoch, HookStatus hookStatus);

    event AllocateLQTY(
        address indexed user,
        address indexed initiative,
        int256 deltaVoteLQTY,
        int256 deltaVetoLQTY,
        uint256 atEpoch,
        HookStatus hookStatus
    );
    event ClaimForInitiative(address indexed initiative, uint256 bold, uint256 forEpoch, HookStatus hookStatus);

    struct Configuration {
        uint256 registrationFee;
        uint256 registrationThresholdFactor;
        uint256 unregistrationThresholdFactor;
        uint256 unregistrationAfterEpochs;
        uint256 votingThresholdFactor;
        uint256 minClaim;
        uint256 minAccrual;
        uint256 epochStart;
        uint256 epochDuration;
        uint256 epochVotingCutoff;
    }

    function registerInitialInitiatives(address[] memory _initiatives) external;

    /// @notice Address of the LQTY StakingV1 contract
    /// @return stakingV1 Address of the LQTY StakingV1 contract
    function stakingV1() external view returns (ILQTYStaking stakingV1);
    /// @notice Address of the LQTY token
    /// @return lqty Address of the LQTY token
    function lqty() external view returns (IERC20 lqty);
    /// @notice Address of the BOLD token
    /// @return bold Address of the BOLD token
    function bold() external view returns (IERC20 bold);
    /// @notice Timestamp at which the first epoch starts
    /// @return epochStart Timestamp at which the first epoch starts
    function EPOCH_START() external view returns (uint256 epochStart);
    /// @notice Duration of an epoch in seconds (e.g. 1 week)
    /// @return epochDuration Epoch duration
    function EPOCH_DURATION() external view returns (uint256 epochDuration);
    /// @notice Voting period of an epoch in seconds (e.g. 6 days)
    /// @return epochVotingCutoff Epoch voting cutoff
    function EPOCH_VOTING_CUTOFF() external view returns (uint256 epochVotingCutoff);
    /// @notice Minimum BOLD amount that has to be claimed, if an initiative doesn't have enough votes to meet the
    /// criteria then it's votes a excluded from the vote count and distribution
    /// @return minClaim Minimum claim amount
    function MIN_CLAIM() external view returns (uint256 minClaim);
    /// @notice Minimum amount of BOLD that have to be accrued for an epoch, otherwise accrual will be skipped for
    /// that epoch
    /// @return minAccrual Minimum amount of BOLD
    function MIN_ACCRUAL() external view returns (uint256 minAccrual);
    /// @notice Amount of BOLD to be paid in order to register a new initiative
    /// @return registrationFee Registration fee
    function REGISTRATION_FEE() external view returns (uint256 registrationFee);
    /// @notice Share of all votes that are necessary to register a new initiative
    /// @return registrationThresholdFactor Threshold factor
    function REGISTRATION_THRESHOLD_FACTOR() external view returns (uint256 registrationThresholdFactor);
    /// @notice Multiple of the voting threshold in vetos that are necessary to unregister an initiative
    /// @return unregistrationThresholdFactor Unregistration threshold factor
    function UNREGISTRATION_THRESHOLD_FACTOR() external view returns (uint256 unregistrationThresholdFactor);
    /// @notice Number of epochs an initiative has to be inactive before it can be unregistered
    /// @return unregistrationAfterEpochs Number of epochs
    function UNREGISTRATION_AFTER_EPOCHS() external view returns (uint256 unregistrationAfterEpochs);
    /// @notice Share of all votes that are necessary for an initiative to be included in the vote count
    /// @return votingThresholdFactor Voting threshold factor
    function VOTING_THRESHOLD_FACTOR() external view returns (uint256 votingThresholdFactor);

    /// @notice Returns the amount of BOLD accrued since last epoch (last snapshot)
    /// @return boldAccrued BOLD accrued
    function boldAccrued() external view returns (uint256 boldAccrued);

    struct VoteSnapshot {
        uint256 votes; // Votes at epoch transition
        uint256 forEpoch; // Epoch for which the votes are counted
    }

    struct InitiativeVoteSnapshot {
        uint256 votes; // Votes at epoch transition
        uint256 forEpoch; // Epoch for which the votes are counted
        uint256 lastCountedEpoch; // Epoch at which which the votes where counted last in the global snapshot
        uint256 vetos; // Vetos at epoch transition
    }

    /// @notice Returns the vote count snapshot of the previous epoch
    /// @return votes Number of votes
    /// @return forEpoch Epoch for which the votes are counted
    function votesSnapshot() external view returns (uint256 votes, uint256 forEpoch);
    /// @notice Returns the vote count snapshot for an initiative of the previous epoch
    /// @param _initiative Address of the initiative
    /// @return votes Number of votes
    /// @return forEpoch Epoch for which the votes are counted
    /// @return lastCountedEpoch Epoch at which which the votes where counted last in the global snapshot
    function votesForInitiativeSnapshot(address _initiative)
        external
        view
        returns (uint256 votes, uint256 forEpoch, uint256 lastCountedEpoch, uint256 vetos);

    struct Allocation {
        uint256 voteLQTY; // LQTY allocated vouching for the initiative
        uint256 voteOffset; // Offset associated with LQTY vouching for the initiative
        uint256 vetoLQTY; // LQTY vetoing the initiative
        uint256 vetoOffset; // Offset associated with LQTY vetoing the initiative
        uint256 atEpoch; // Epoch at which the allocation was last updated
    }

    struct UserState {
        uint256 unallocatedLQTY; // LQTY deposited and unallocated
        uint256 unallocatedOffset; // The offset sum corresponding to the unallocated LQTY
        uint256 allocatedLQTY; // LQTY allocated by the user to initatives
        uint256 allocatedOffset; // The offset sum corresponding to the allocated LQTY
    }

    struct InitiativeState {
        uint256 voteLQTY; // LQTY allocated vouching for the initiative
        uint256 voteOffset; // Offset associated with LQTY vouching for to the initative
        uint256 vetoLQTY; // LQTY allocated vetoing the initiative
        uint256 vetoOffset; // Offset associated with LQTY veoting the initative
        uint256 lastEpochClaim;
    }

    struct GlobalState {
        uint256 countedVoteLQTY; // Total LQTY that is included in vote counting
        uint256 countedVoteOffset; // Offset associated with the counted vote LQTY
    }

    /// @notice Returns the user's state
    /// @return unallocatedLQTY LQTY deposited and unallocated
    /// @return unallocatedOffset Offset associated with unallocated LQTY
    /// @return allocatedLQTY allocated by the user to initatives
    /// @return allocatedOffset Offset associated with allocated LQTY
    function userStates(address _user)
        external
        view
        returns (uint256 unallocatedLQTY, uint256 unallocatedOffset, uint256 allocatedLQTY, uint256 allocatedOffset);
    /// @notice Returns the initiative's state
    /// @param _initiative Address of the initiative
    /// @return voteLQTY LQTY allocated vouching for the initiative
    /// @return voteOffset Offset associated with voteLQTY
    /// @return vetoLQTY LQTY allocated vetoing the initiative
    /// @return vetoOffset Offset associated with vetoLQTY
    /// @return lastEpochClaim // Last epoch at which rewards were claimed
    function initiativeStates(address _initiative)
        external
        view
        returns (uint256 voteLQTY, uint256 voteOffset, uint256 vetoLQTY, uint256 vetoOffset, uint256 lastEpochClaim);
    /// @notice Returns the global state
    /// @return countedVoteLQTY Total LQTY that is included in vote counting
    /// @return countedVoteOffset Offset associated with countedVoteLQTY
    function globalState() external view returns (uint256 countedVoteLQTY, uint256 countedVoteOffset);
    /// @notice Returns the amount of voting and vetoing LQTY a user allocated to an initiative
    /// @param _user Address of the user
    /// @param _initiative Address of the initiative
    /// @return voteLQTY LQTY allocated vouching for the initiative
    /// @return voteOffset The offset associated with voteLQTY
    /// @return vetoLQTY allocated vetoing the initiative
    /// @return vetoOffset the offset associated with vetoLQTY
    /// @return atEpoch Epoch at which the allocation was last updated
    function lqtyAllocatedByUserToInitiative(address _user, address _initiative)
        external
        view
        returns (uint256 voteLQTY, uint256 voteOffset, uint256 vetoLQTY, uint256 vetoOffset, uint256 atEpoch);

    /// @notice Returns when an initiative was registered
    /// @param _initiative Address of the initiative
    /// @return atEpoch If `_initiative` is an active initiative, returns the epoch at which it was registered.
    ///                 If `_initiative` hasn't been registered, returns 0.
    ///                 If `_initiative` has been unregistered, returns `UNREGISTERED_INITIATIVE`.
    function registeredInitiatives(address _initiative) external view returns (uint256 atEpoch);

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits LQTY
    /// @dev The caller has to approve their `UserProxy` address to spend the LQTY tokens
    /// @param _lqtyAmount Amount of LQTY to deposit
    function depositLQTY(uint256 _lqtyAmount) external;

    /// @notice Deposits LQTY
    /// @dev The caller has to approve their `UserProxy` address to spend the LQTY tokens
    /// @param _lqtyAmount Amount of LQTY to deposit
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    function depositLQTY(uint256 _lqtyAmount, bool _doSendRewards, address _recipient) external;

    /// @notice Deposits LQTY via Permit
    /// @param _lqtyAmount Amount of LQTY to deposit
    /// @param _permitParams Permit parameters
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams calldata _permitParams) external;

    /// @notice Deposits LQTY via Permit
    /// @param _lqtyAmount Amount of LQTY to deposit
    /// @param _permitParams Permit parameters
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    function depositLQTYViaPermit(
        uint256 _lqtyAmount,
        PermitParams calldata _permitParams,
        bool _doSendRewards,
        address _recipient
    ) external;

    /// @notice Withdraws LQTY and claims any accrued LUSD and ETH rewards from StakingV1
    /// @param _lqtyAmount Amount of LQTY to withdraw
    function withdrawLQTY(uint256 _lqtyAmount) external;

    /// @notice Withdraws LQTY and claims any accrued LUSD and ETH rewards from StakingV1
    /// @param _lqtyAmount Amount of LQTY to withdraw
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    function withdrawLQTY(uint256 _lqtyAmount, bool _doSendRewards, address _recipient) external;

    /// @notice Claims staking rewards from StakingV1 without unstaking
    /// @dev Note: in the unlikely event that the caller's `UserProxy` holds any LQTY tokens, they will also be sent to `_rewardRecipient`
    /// @param _rewardRecipient Address that will receive the rewards
    /// @return lusdSent Amount of LUSD tokens sent to `_rewardRecipient` (may include previously received LUSD)
    /// @return ethSent Amount of ETH sent to `_rewardRecipient` (may include previously received ETH)
    function claimFromStakingV1(address _rewardRecipient) external returns (uint256 lusdSent, uint256 ethSent);

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current epoch number
    /// @return epoch Current epoch
    function epoch() external view returns (uint256 epoch);
    /// @notice Returns the timestamp at which the current epoch started
    /// @return epochStart Epoch start of the current epoch
    function epochStart() external view returns (uint256 epochStart);
    /// @notice Returns the number of seconds that have gone by since the current epoch started
    /// @return secondsWithinEpoch Seconds within the current epoch
    function secondsWithinEpoch() external view returns (uint256 secondsWithinEpoch);

    /// @notice Returns the voting power for an entity (i.e. user or initiative) at a given timestamp
    /// @param _lqtyAmount Amount of LQTY associated with the entity
    /// @param _timestamp Timestamp at which to calculate voting power
    /// @param _offset The entity's offset sum
    /// @return votes Number of votes
    function lqtyToVotes(uint256 _lqtyAmount, uint256 _timestamp, uint256 _offset) external pure returns (uint256);

    /// @dev Returns the most up to date voting threshold
    /// In contrast to `getLatestVotingThreshold` this function updates the snapshot
    /// This ensures that the value returned is always the latest
    function calculateVotingThreshold() external returns (uint256);

    /// @dev Utility function to compute the threshold votes without recomputing the snapshot
    /// Note that `boldAccrued` is a cached value, this function works correctly only when called after an accrual
    function calculateVotingThreshold(uint256 _votes) external view returns (uint256);

    /// @notice Return the most up to date global snapshot and state as well as a flag to notify whether the state can be updated
    /// This is a convenience function to always retrieve the most up to date state values
    function getTotalVotesAndState()
        external
        view
        returns (VoteSnapshot memory snapshot, GlobalState memory state, bool shouldUpdate);

    /// @dev Given an initiative address, return it's most up to date snapshot and state as well as a flag to notify whether the state can be updated
    /// This is a convenience function to always retrieve the most up to date state values
    function getInitiativeSnapshotAndState(address _initiative)
        external
        view
        returns (
            InitiativeVoteSnapshot memory initiativeSnapshot,
            InitiativeState memory initiativeState,
            bool shouldUpdate
        );

    /// @notice Voting threshold is the max. of either:
    ///   - 4% of the total voting LQTY in the previous epoch
    ///   - or the minimum number of votes necessary to claim at least MIN_CLAIM BOLD
    /// This value can be offsynch, use the non view `calculateVotingThreshold` to always retrieve the most up to date value
    /// @return votingThreshold Voting threshold
    function getLatestVotingThreshold() external view returns (uint256 votingThreshold);

    /// @notice Snapshots votes for the previous epoch and accrues funds for the current epoch
    /// @param _initiative Address of the initiative
    /// @return voteSnapshot Vote snapshot
    /// @return initiativeVoteSnapshot Vote snapshot of the initiative
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot);

    /*//////////////////////////////////////////////////////////////
                                 FSM
    //////////////////////////////////////////////////////////////*/

    enum InitiativeStatus {
        NONEXISTENT,
        /// This Initiative Doesn't exist | This is never returned
        WARM_UP,
        /// This epoch was just registered
        SKIP,
        /// This epoch will result in no rewards and no unregistering
        CLAIMABLE,
        /// This epoch will result in claiming rewards
        CLAIMED,
        /// The rewards for this epoch have been claimed
        UNREGISTERABLE,
        /// Can be unregistered
        DISABLED // It was already Unregistered

    }

    function getInitiativeState(address _initiative)
        external
        returns (InitiativeStatus status, uint256 lastEpochClaim, uint256 claimableAmount);

    function getInitiativeState(
        address _initiative,
        VoteSnapshot memory _votesSnapshot,
        InitiativeVoteSnapshot memory _votesForInitiativeSnapshot,
        InitiativeState memory _initiativeState
    ) external view returns (InitiativeStatus status, uint256 lastEpochClaim, uint256 claimableAmount);

    /// @notice Registers a new initiative
    /// @param _initiative Address of the initiative
    function registerInitiative(address _initiative) external;
    // /// @notice Unregisters an initiative if it didn't receive enough votes in the last 4 epochs
    // /// or if it received more vetos than votes and the number of vetos are greater than 3 times the voting threshold
    // /// @param _initiative Address of the initiative
    function unregisterInitiative(address _initiative) external;

    /// @notice Allocates the user's LQTY to initiatives
    /// @dev The user can only allocate to active initiatives (older than 1 epoch) and has to have enough unallocated
    /// LQTY available, the initiatives listed must be unique, and towards the end of the epoch a user can only maintain or reduce their votes
    /// @param _initiativesToReset Addresses of the initiatives the caller was previously allocated to, must be reset to prevent desynch of voting power
    /// @param _initiatives Addresses of the initiatives to allocate to, can match or be different from `_resetInitiatives`
    /// @param _absoluteLQTYVotes LQTY to allocate to the initiatives as votes
    /// @param _absoluteLQTYVetos LQTY to allocate to the initiatives as vetos
    function allocateLQTY(
        address[] calldata _initiativesToReset,
        address[] memory _initiatives,
        int256[] memory _absoluteLQTYVotes,
        int256[] memory _absoluteLQTYVetos
    ) external;
    /// @notice Deallocates the user's LQTY from initiatives
    /// @param _initiativesToReset Addresses of initiatives to deallocate LQTY from
    /// @param _checkAll When true, the call will revert if there is still some allocated LQTY left after deallocating
    ///                  from all the addresses in `_initiativesToReset`
    function resetAllocations(address[] calldata _initiativesToReset, bool _checkAll) external;

    /// @notice Splits accrued funds according to votes received between all initiatives
    /// @param _initiative Addresse of the initiative
    /// @return claimed Amount of BOLD claimed
    function claimForInitiative(address _initiative) external returns (uint256 claimed);
}
