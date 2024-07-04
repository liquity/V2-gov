// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {PermitParams} from "../utils/Types.sol";

interface IGovernance {
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
    /// @notice Reference timestamp used to derive the current share rate
    function EPOCH_DURATION() external view returns (uint256);
    /// @notice Duration of an epoch in seconds (e.g. 1 week)
    function EPOCH_START() external view returns (uint256);
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

    /// @notice Total shares in circulation
    function totalShares() external view returns (uint256);
    /// @notice Mapping of each user's share balance
    function sharesByUser(address) external view returns (uint256);

    /// @notice Initiatives registered, by address
    function initiativesRegistered(address) external view returns (uint256);

    /// @notice BOLD accrued since last epoch
    function boldAccrued() external view returns (uint256);

    /// @notice Total number of shares allocated to initiatives that meet the voting threshold and are included
    /// in vote counting
    function qualifyingShares() external view returns (uint256);

    struct Snapshot {
        uint240 votes;
        uint16 forEpoch;
    }

    /// @notice Number of votes at the last epoch
    function votesSnapshot() external view returns (uint240 votes, uint16 forEpoch);
    /// @notice Number of votes received by an initiative at the last epoch
    function votesForInitiativeSnapshot(address) external view returns (uint240 votes, uint16 forEpoch);

    struct UserAllocation {
        uint192 shares;
        uint16 atEpoch;
    }

    /// @notice Number of shares (shares + vetoShares) allocated by user
    function sharesAllocatedByUser(address) external view returns (uint192 shares, uint16 atEpoch);

    struct ShareAllocation {
        uint128 shares; // Shares allocated vouching for the initiative
        uint128 vetoShares; // Shares vetoing the initiative
    }

    /// @notice Shares (shares + vetoShares) allocated to initiatives
    function sharesAllocatedToInitiative(address) external view returns (uint128 shares, uint128 vetoShares);
    /// @notice Shares (shares + vetoShares) allocated by user to initiatives
    function sharesAllocatedByUserToInitiative(address, address)
        external
        view
        returns (uint128 shares, uint128 vetoShares);

    /// @notice Returns the current share rate based on the time since deployment
    function currentShareRate() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits LQTY and mints shares based on the current share rate
    function depositLQTY(uint256 _lqtyAmount) external returns (uint256);
    /// @notice Deposits LQTY via Permit and mints shares based on the current share rate
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams memory _permitParams) external returns (uint256);
    /// @notice Withdraws LQRT by burning the shares and claim any accrued LUSD and ETH rewards from StakingV1
    function withdrawShares(uint256 _shareAmount) external returns (uint256);

    function transferShares(uint256 _shareAmount, address _to) external;

    /// @notice Claims staking rewards from StakingV1 without unstaking
    function claimFromStakingV1() external;

    /*//////////////////////////////////////////////////////////////
                                 VOTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current epoch number
    function epoch() external view returns (uint16);
    /// @notice Returns the number of seconds until the next epoch
    function secondsUntilNextEpoch() external view returns (uint256);
    /// @notice Voting power of a share linearly increases over time starting from 0 at time of share issuance
    function sharesToVotes(uint256 _shareRate, uint256 _shares) external pure returns (uint256);

    /// @notice Voting threshold is the max. of either:
    ///   - 4% of total shares allocated in the previous epoch
    ///   - or the minimum number of votes necessary to claim at least MIN_CLAIM BOLD
    function calculateVotingThreshold() external view returns (uint256);

    /// @notice Snapshots votes for the previous epoch and accrues funds for the current epoch
    function snapshotVotesForInitiative(address _initiative)
        external
        returns (Snapshot memory votes, Snapshot memory votesForInitiative);

    /// @notice Registers a new initiative
    function registerInitiative(address _initiative) external;
    /// @notice Unregisters an initiative if it didn't receive enough votes in the last 4 epochs
    /// or if it received more vetos than votes and the number of vetos are greater than 3 times the voting threshold
    function unregisterInitiative(address _initiative) external;

    /// @notice Allocates the user's shares to initiatives either as vote shares or veto shares
    function allocateShares(
        address[] memory _initiatives,
        int256[] memory _deltaShares,
        int256[] memory _deltaVetoShares
    ) external;

    /// @notice Splits accrued funds according to votes received between all initiatives
    function claimForInitiative(address _initiative) external returns (uint256);
}
