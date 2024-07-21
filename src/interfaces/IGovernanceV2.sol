// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {PermitParams} from "../utils/Types.sol";

interface IGovernanceV2 {
    event DepositLQTY(address user, uint256 depositedLQTY);
    event WithdrawLQTY(
        address user, uint256 withdrawnLQTY, uint256 accruedLQTY_, uint256 accruedLUSD, uint256 accruedETH
    );

    event SnapshotVotes(uint240 votes, uint16 forEpoch);
    event SnapshotVotesForInitiative(address initiative, uint240 votes, uint16 forEpoch);

    event RegisterInitiative(address initiative, address registrant, uint16 atEpoch);
    event UnregisterInitiative(address initiative, uint16 atEpoch);

    event AllocateLQTY(address user, address initiative, int256 deltaVoteLQTY, int256 deltaVetoLQTY, uint16 atEpoch);
    event ClaimForInitiative(address initiative, uint256 bold, uint256 forEpoch);

    struct Configuration {
        uint256 registrationFee;
        uint256 regstrationThresholdFactor;
        uint256 votingThresholdFactor;
        uint256 minClaim;
        uint256 minAccrual;
        uint256 epochStart;
        uint256 epochDuration;
        uint256 epochVotingCutoff;
    }

    /// @notice Address of the BOLD token
    function bold() external view returns (IERC20);
    /// @notice Reference timestamp ...
    function EPOCH_START() external view returns (uint256);
    /// @notice Duration of an epoch in seconds (e.g. 1 week)
    function EPOCH_DURATION() external view returns (uint256);
    /// @notice Voting period of an epoch in seconds (e.g. 6 days)
    function EPOCH_VOTING_CUTOFF() external view returns (uint256);
    /// @notice Minimum BOLD amount that can be claimed, if an initiative doesn't have enough votes to meet the
    /// criteria then it's votes a excluded from the vote count and distribution
    function MIN_CLAIM() external view returns (uint256);
    /// @notice Minimum amount of BOLD that have to be accrued for an epoch, otherwise accrual will be skipped for
    /// that epoch
    function MIN_ACCRUAL() external view returns (uint256);
    /// @notice Amount of BOLD to be paid in order to register a new initiative
    function REGISTRATION_FEE() external view returns (uint256);
    /// @notice Share of all votes that are necessary to register a new initiative
    function REGISTRATION_THRESHOLD_FACTOR() external view returns (uint256);
    /// @notice Share of all votes that are necessary for an initiative to be included in the vote count
    function VOTING_THRESHOLD_FACTOR() external view returns (uint256);

    /// @notice BOLD accrued since last epoch
    function boldAccrued() external view returns (uint256);

    struct VoteSnapshot {
        uint240 votes; // Votes at epoch transition
        uint16 forEpoch; // Epoch for which the votes are counted
    }

    struct InitiativeVoteSnapshot {
        uint240 votes; // Votes at epoch transition
        uint16 forEpoch; // Epoch for which the votes are counted
    }

    /// @notice Number of votes at the last epoch
    function votesSnapshot() external view returns (uint240 votes, uint16 forEpoch);
    /// @notice Number of votes received by an initiative at the last epoch
    function votesForInitiativeSnapshot(address) external view returns (uint240 votes, uint16 forEpoch);

    struct Allocation {
        uint96 voteLQTY; // LQTY allocated vouching for the initiative
        uint96 vetoLQTY; // LQTY vetoing the initiative
        uint16 atEpoch; // Epoch at which the allocation was last updated
    }

    struct UserState {
        uint96 allocatedLQTY; // LQTY allocated by the user
        uint32 averageStakingTimestamp; // Average timestamp at which LQTY was staked by the user
    }

    struct InitiativeState {
        uint96 voteLQTY; // LQTY allocated vouching for the initiative
        uint96 vetoLQTY; // LQTY allocated vetoing the initiative
        uint8 counted; // Whether votes were counted 'atEpoch' (included in 'globalAllocation.countedLQTY')
        uint8 active; // Whether the initiative can receive allocations
        uint16 atEpoch; // Epoch at which the allocation was last updated
        uint32 averageStakingTimestamp; // Average timestamp at which LQTY was allocated to the initiative
    }

    struct GlobalState {
        uint96 totalStakedLQTY; // Total LQTY staked
        uint32 totalStakedLQTYAverageTimestamp; // Average timestamp at which LQTY was staked
        uint96 countedVoteLQTY; // Total LQTY that is included in vote counting
        uint32 countedVoteLQTYAverageTimestamp; // Average timestamp: derived initiativeAllocation.averageTimestamp
    }

    /// @notice Returns the user's state
    function userStates(address) external view returns (uint96 allocatedLQTY, uint32 averageStakingTimestamp);
    /// @notice Returns the initiative's state
    function initiativeStates(address)
        external
        view
        returns (
            uint96 voteLQTY,
            uint96 vetoLQTY,
            uint8 counted,
            uint8 active,
            uint16 atEpoch,
            uint32 averageStakingTimestamp
        );
    /// @notice Returns the global state
    function globalState()
        external
        view
        returns (
            uint96 totalStakedLQTY,
            uint32 totalStakedLQTYAverageTimestamp,
            uint96 countedVoteLQTY,
            uint32 countedVoteLQTYAverageTimestamp
        );
    /// @notice Returns the amount of voting and vetoing LQTY a user allocated to an initiative
    function lqtyAllocatedByUserToInitiative(address, address)
        external
        view
        returns (uint96 voteLQTY, uint96 vetoLQTY, uint16 atEpoch);

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits LQTY
    function depositLQTY(uint96 _lqtyAmount) external;
    /// @notice Deposits LQTY via Permit
    function depositLQTYViaPermit(uint96 _lqtyAmount, PermitParams memory _permitParams) external;
    /// @notice Withdraws LQTY and claims any accrued LUSD and ETH rewards from StakingV1
    function withdrawLQTY(uint96 _lqtyAmount) external;
    /// @notice Claims staking rewards from StakingV1 without unstaking
    function claimFromStakingV1(address _rewardRecipient) external;

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current epoch number
    function epoch() external view returns (uint16);
    /// @notice Returns the timestamp at which the current epoch started
    function epochStart() external view returns (uint32);
    /// @notice Returns the number of seconds that have gone by since the current epoch started
    function secondsWithinEpoch() external view returns (uint32);
    /// @notice Returns the number of votes per LQTY for a user
    function lqtyToVotes(uint96 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp)
        external
        pure
        returns (uint240);

    /// @notice Voting threshold is the max. of either:
    ///   - 4% of the total voting LQTY in the previous epoch
    ///   - or the minimum number of votes necessary to claim at least MIN_CLAIM BOLD
    function calculateVotingThreshold() external view returns (uint256);

    /// @notice Snapshots votes for the previous epoch and accrues funds for the current epoch
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (VoteSnapshot memory voteSnapshot, InitiativeVoteSnapshot memory initiativeVoteSnapshot);

    /// @notice Registers a new initiative
    function registerInitiative(address _initiative) external;
    // /// @notice Unregisters an initiative if it didn't receive enough votes in the last 4 epochs
    // /// or if it received more vetos than votes and the number of vetos are greater than 3 times the voting threshold
    function unregisterInitiative(address _initiative) external;

    /// @notice Allocates the user's LQTY to initiatives
    function allocateLQTY(
        address[] memory _initiatives,
        int192[] memory _deltaLQTYVotes,
        int192[] memory _deltaLQTYVetos
    ) external;

    /// @notice Splits accrued funds according to votes received between all initiatives
    function claimForInitiative(address _initiative) external returns (uint256);
}
