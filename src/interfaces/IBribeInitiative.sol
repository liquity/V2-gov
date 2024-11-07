// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./IGovernance.sol";

interface IBribeInitiative {
    event DepositBribe(address depositor, uint128 boldAmount, uint128 bribeTokenAmount, uint16 epoch);
    event ModifyLQTYAllocation(address user, uint16 epoch, uint88 lqtyAllocated, uint32 averageTimestamp);
    event ModifyTotalLQTYAllocation(uint16 epoch, uint88 totalLQTYAllocated, uint32 averageTimestamp);
    event ClaimBribe(address user, uint16 epoch, uint256 boldAmount, uint256 bribeTokenAmount);

    /// @notice Address of the governance contract
    /// @return governance Adress of the governance contract
    function governance() external view returns (IGovernance governance);
    /// @notice Address of the BOLD token
    /// @return bold Address of the BOLD token
    function bold() external view returns (IERC20 bold);
    /// @notice Address of the bribe token
    /// @return bribeToken Address of the bribe token
    function bribeToken() external view returns (IERC20 bribeToken);

    struct Bribe {
        uint128 boldAmount;
        uint128 bribeTokenAmount; // [scaled as 10 ** bribeToken.decimals()]
    }

    /// @notice Amount of bribe tokens deposited for a given epoch
    /// @param _epoch Epoch at which the bribe was deposited
    /// @return boldAmount Amount of BOLD tokens deposited
    /// @return bribeTokenAmount Amount of bribe tokens deposited
    function bribeByEpoch(uint16 _epoch) external view returns (uint128 boldAmount, uint128 bribeTokenAmount);
    /// @notice Check if a user has claimed bribes for a given epoch
    /// @param _user Address of the user
    /// @param _epoch Epoch at which the bribe may have been claimed by the user
    /// @return claimed If the user has claimed the bribe
    function claimedBribeAtEpoch(address _user, uint16 _epoch) external view returns (bool claimed);

    /// @notice Total LQTY allocated to the initiative at a given epoch
    /// @param _epoch Epoch at which the LQTY was allocated
    /// @return totalLQTYAllocated Total LQTY allocated
    function totalLQTYAllocatedByEpoch(uint16 _epoch)
        external
        view
        returns (uint88 totalLQTYAllocated, uint32 averageTimestamp);
    /// @notice LQTY allocated by a user to the initiative at a given epoch
    /// @param _user Address of the user
    /// @param _epoch Epoch at which the LQTY was allocated by the user
    /// @return lqtyAllocated LQTY allocated by the user
    function lqtyAllocatedByUserAtEpoch(address _user, uint16 _epoch)
        external
        view
        returns (uint88 lqtyAllocated, uint32 averageTimestamp);

    /// @notice Deposit bribe tokens for a given epoch
    /// @dev The caller has to approve this contract to spend the BOLD and bribe tokens.
    /// The caller can only deposit bribes for future epochs
    /// @param _boldAmount Amount of BOLD tokens to deposit
    /// @param _bribeTokenAmount Amount of bribe tokens to deposit
    /// @param _epoch Epoch at which the bribe is deposited
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint16 _epoch) external;

    struct ClaimData {
        // Epoch at which the user wants to claim the bribes
        uint16 epoch;
        // Epoch at which the user updated the LQTY allocation for this initiative
        uint16 prevLQTYAllocationEpoch;
        // Epoch at which the total LQTY allocation is updated for this initiative
        uint16 prevTotalLQTYAllocationEpoch;
    }

    /// @notice Claim bribes for a user
    /// @dev The user can only claim bribes for past epochs.
    /// The arrays `_epochs`, `_prevLQTYAllocationEpochs` and `_prevTotalLQTYAllocationEpochs` should be sorted
    /// from oldest epoch to the newest. The length of the arrays has to be the same.
    /// @param _claimData Array specifying the epochs at which the user wants to claim the bribes
    function claimBribes(ClaimData[] calldata _claimData)
        external
        returns (uint256 boldAmount, uint256 bribeTokenAmount);

    /// @notice Given a user address return the last recorded epoch for their allocation
    function getMostRecentUserEpoch(address _user) external view returns (uint16);

    /// @notice Return the last recorded epoch for the system
    function getMostRecentTotalEpoch() external view returns (uint16);
}
