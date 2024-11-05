// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "./ILQTYStaking.sol";

import {PermitParams} from "../utils/Types.sol";

interface IGovernance {
    event DepositLQTY(address user, uint256 depositedLQTY);
    event WithdrawLQTY(address user, uint256 withdrawnLQTY, uint256 accruedLUSD, uint256 accruedETH);

    event SnapshotVotes(uint240 votes, uint16 forEpoch);
    event SnapshotVotesForInitiative(address initiative, uint240 votes, uint16 forEpoch);

    event RegisterInitiative(address initiative, address registrant, uint16 atEpoch);
    event UnregisterInitiative(address initiative, uint16 atEpoch);

    event AllocateLQTY(address user, address initiative, int256 deltaVoteLQTY, int256 deltaVetoLQTY, uint16 atEpoch);
    event ClaimForInitiative(address initiative, uint256 bold, uint256 forEpoch);

    struct Configuration {
        uint128 registrationFee;
        uint128 registrationThresholdFactor;
        uint128 unregistrationThresholdFactor;
        uint16 registrationWarmUpPeriod;
        uint16 unregistrationAfterEpochs;
        uint128 votingThresholdFactor;
        uint88 minClaim;
        uint88 minAccrual;
        uint32 epochStart;
        uint32 epochDuration;
        uint32 epochVotingCutoff;
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
    /// @notice Number of epochs an initiative has to exist before it can be unregistered
    /// @return registrationWarmUpPeriod Number of epochs
    function REGISTRATION_WARM_UP_PERIOD() external view returns (uint256 registrationWarmUpPeriod);
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
        uint240 votes; // Votes at epoch transition
        uint16 forEpoch; // Epoch for which the votes are counted
    }

    struct InitiativeVoteSnapshot {
        uint224 votes; // Votes at epoch transition
        uint16 forEpoch; // Epoch for which the votes are counted
        uint16 lastCountedEpoch; // Epoch at which which the votes where counted last in the global snapshot
        uint224 vetos; // Vetos at epoch transition
    }

    /// @notice Returns the vote count snapshot of the previous epoch
    /// @return votes Number of votes
    /// @return forEpoch Epoch for which the votes are counted
    function votesSnapshot() external view returns (uint240 votes, uint16 forEpoch);
    /// @notice Returns the vote count snapshot for an initiative of the previous epoch
    /// @param _initiative Address of the initiative
    /// @return votes Number of votes
    /// @return forEpoch Epoch for which the votes are counted
    /// @return lastCountedEpoch Epoch at which which the votes where counted last in the global snapshot
    function votesForInitiativeSnapshot(address _initiative)
        external
        view
        returns (uint224 votes, uint16 forEpoch, uint16 lastCountedEpoch, uint224 vetos);

    struct Allocation {
        uint88 voteLQTY; // LQTY allocated vouching for the initiative
        uint88 vetoLQTY; // LQTY vetoing the initiative
        uint16 atEpoch; // Epoch at which the allocation was last updated
    }

    struct UserState {
        uint88 allocatedLQTY; // LQTY allocated by the user
        uint32 averageStakingTimestamp; // Average timestamp at which LQTY was staked by the user
    }

    struct InitiativeState {
        uint88 voteLQTY; // LQTY allocated vouching for the initiative
        uint88 vetoLQTY; // LQTY allocated vetoing the initiative
        uint32 averageStakingTimestampVoteLQTY; // Average staking timestamp of the voting LQTY for the initiative
        uint32 averageStakingTimestampVetoLQTY; // Average staking timestamp of the vetoing LQTY for the initiative
        uint16 lastEpochClaim;
    }

    struct GlobalState {
        uint88 countedVoteLQTY; // Total LQTY that is included in vote counting
        uint32 countedVoteLQTYAverageTimestamp; // Average timestamp: derived initiativeAllocation.averageTimestamp
    }
    /// TODO: Bold balance? Prob cheaper

    /// @notice Returns the user's state
    /// @param _user Address of the user
    /// @return allocatedLQTY LQTY allocated by the user
    /// @return averageStakingTimestamp Average timestamp at which LQTY was staked (deposited) by the user
    function userStates(address _user) external view returns (uint88 allocatedLQTY, uint32 averageStakingTimestamp);
    /// @notice Returns the initiative's state
    /// @param _initiative Address of the initiative
    /// @return voteLQTY LQTY allocated vouching for the initiative
    /// @return vetoLQTY LQTY allocated vetoing the initiative
    /// @return averageStakingTimestampVoteLQTY // Average staking timestamp of the voting LQTY for the initiative
    /// @return averageStakingTimestampVetoLQTY // Average staking timestamp of the vetoing LQTY for the initiative
    /// @return lastEpochClaim // Last epoch at which rewards were claimed
    function initiativeStates(address _initiative)
        external
        view
        returns (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
            uint16 lastEpochClaim
        );
    /// @notice Returns the global state
    /// @return countedVoteLQTY Total LQTY that is included in vote counting
    /// @return countedVoteLQTYAverageTimestamp Average timestamp: derived initiativeAllocation.averageTimestamp
    function globalState() external view returns (uint88 countedVoteLQTY, uint32 countedVoteLQTYAverageTimestamp);
    /// @notice Returns the amount of voting and vetoing LQTY a user allocated to an initiative
    /// @param _user Address of the user
    /// @param _initiative Address of the initiative
    /// @return voteLQTY LQTY allocated vouching for the initiative
    /// @return vetoLQTY LQTY allocated vetoing the initiative
    /// @return atEpoch Epoch at which the allocation was last updated
    function lqtyAllocatedByUserToInitiative(address _user, address _initiative)
        external
        view
        returns (uint88 voteLQTY, uint88 vetoLQTY, uint16 atEpoch);

    /// @notice Returns when an initiative was registered
    /// @param _initiative Address of the initiative
    /// @return atEpoch Epoch at which the initiative was registered
    function registeredInitiatives(address _initiative) external view returns (uint16 atEpoch);

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits LQTY
    /// @dev The caller has to approve this contract to spend the LQTY tokens
    /// @param _lqtyAmount Amount of LQTY to deposit
    function depositLQTY(uint88 _lqtyAmount) external;
    /// @notice Deposits LQTY via Permit
    /// @param _lqtyAmount Amount of LQTY to deposit
    /// @param _permitParams Permit parameters
    function depositLQTYViaPermit(uint88 _lqtyAmount, PermitParams memory _permitParams) external;
    /// @notice Withdraws LQTY and claims any accrued LUSD and ETH rewards from StakingV1
    /// @param _lqtyAmount Amount of LQTY to withdraw
    function withdrawLQTY(uint88 _lqtyAmount) external;
    /// @notice Claims staking rewards from StakingV1 without unstaking
    /// @param _rewardRecipient Address that will receive the rewards
    /// @return accruedLUSD Amount of LUSD accrued
    /// @return accruedETH Amount of ETH accrued
    function claimFromStakingV1(address _rewardRecipient) external returns (uint256 accruedLUSD, uint256 accruedETH);

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current epoch number
    /// @return epoch Current epoch
    function epoch() external view returns (uint16 epoch);
    /// @notice Returns the timestamp at which the current epoch started
    /// @return epochStart Epoch start of the current epoch
    function epochStart() external view returns (uint32 epochStart);
    /// @notice Returns the number of seconds that have gone by since the current epoch started
    /// @return secondsWithinEpoch Seconds within the current epoch
    function secondsWithinEpoch() external view returns (uint32 secondsWithinEpoch);
    /// @notice Returns the number of votes per LQTY for a user
    /// @param _lqtyAmount Amount of LQTY to convert to votes
    /// @param _currentTimestamp Current timestamp
    /// @param _averageTimestamp Average timestamp at which the LQTY was staked
    /// @return votes Number of votes
    function lqtyToVotes(uint88 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp)
        external
        pure
        returns (uint240);

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
    /// @param _resetInitiatives Addresses of the initiatives the caller was previously allocated to, must be reset to prevent desynch of voting power
    /// @param _initiatives Addresses of the initiatives to allocate to, can match or be different from `_resetInitiatives`
    /// @param _absoluteLQTYVotes Delta LQTY to allocate to the initiatives as votes
    /// @param absoluteLQTYVetos Delta LQTY to allocate to the initiatives as vetos
    function allocateLQTY(
        address[] calldata _resetInitiatives,
        address[] memory _initiatives,
        int88[] memory _absoluteLQTYVotes,
        int88[] memory absoluteLQTYVetos
    ) external;

    /// @notice Splits accrued funds according to votes received between all initiatives
    /// @param _initiative Addresse of the initiative
    /// @return claimed Amount of BOLD claimed
    function claimForInitiative(address _initiative) external returns (uint256 claimed);
}
