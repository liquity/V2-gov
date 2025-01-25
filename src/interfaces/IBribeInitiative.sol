// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./IGovernance.sol";

interface IBribeInitiative {
    event DepositBribe(address depositor, uint256 boldAmount, uint256 bribeTokenAmount, uint256 epoch);
    event ModifyLQTYAllocation(address user, uint256 epoch, uint256 lqtyAllocated, uint256 offset);
    event ModifyTotalLQTYAllocation(uint256 epoch, uint256 totalLQTYAllocated, uint256 offset);
    event ClaimBribe(address user, uint256 epoch, uint256 boldAmount, uint256 bribeTokenAmount);

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
        uint256 remainingBoldAmount;
        uint256 remainingBribeTokenAmount; // [scaled as 10 ** bribeToken.decimals()]
        uint256 claimedVotes;
    }

    /// @notice Amount of bribe tokens deposited for a given epoch
    /// @param _epoch Epoch at which the bribe was deposited
    /// @return remainingBoldAmount Amount of BOLD tokens that haven't been claimed yet
    /// @return remainingBribeTokenAmount Amount of bribe tokens that haven't been claimed yet
    /// @return claimedVotes Sum of voting power of users who have already claimed their bribes
    function bribeByEpoch(uint256 _epoch)
        external
        view
        returns (uint256 remainingBoldAmount, uint256 remainingBribeTokenAmount, uint256 claimedVotes);
    /// @notice Check if a user has claimed bribes for a given epoch
    /// @param _user Address of the user
    /// @param _epoch Epoch at which the bribe may have been claimed by the user
    /// @return claimed If the user has claimed the bribe
    function claimedBribeAtEpoch(address _user, uint256 _epoch) external view returns (bool claimed);

    /// @notice Total LQTY allocated to the initiative at a given epoch
    ///         Voting power can be calculated as `totalLQTYAllocated * timestamp - offset`
    /// @param _epoch Epoch at which the LQTY was allocated
    /// @return totalLQTYAllocated Total LQTY allocated
    /// @return offset Voting power offset
    function totalLQTYAllocatedByEpoch(uint256 _epoch)
        external
        view
        returns (uint256 totalLQTYAllocated, uint256 offset);
    /// @notice LQTY allocated by a user to the initiative at a given epoch
    ///         Voting power can be calculated as `lqtyAllocated * timestamp - offset`
    /// @param _user Address of the user
    /// @param _epoch Epoch at which the LQTY was allocated by the user
    /// @return lqtyAllocated LQTY allocated by the user
    /// @return offset Voting power offset
    function lqtyAllocatedByUserAtEpoch(address _user, uint256 _epoch)
        external
        view
        returns (uint256 lqtyAllocated, uint256 offset);

    /// @notice Deposit bribe tokens for a given epoch
    /// @dev The caller has to approve this contract to spend the BOLD and bribe tokens.
    /// The caller can only deposit bribes for future epochs
    /// @param _boldAmount Amount of BOLD tokens to deposit
    /// @param _bribeTokenAmount Amount of bribe tokens to deposit
    /// @param _epoch Epoch at which the bribe is deposited
    function depositBribe(uint256 _boldAmount, uint256 _bribeTokenAmount, uint256 _epoch) external;

    struct ClaimData {
        // Epoch at which the user wants to claim the bribes
        uint256 epoch;
        // Epoch at which the user updated the LQTY allocation for this initiative
        uint256 prevLQTYAllocationEpoch;
        // Epoch at which the total LQTY allocation is updated for this initiative
        uint256 prevTotalLQTYAllocationEpoch;
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
    function getMostRecentUserEpoch(address _user) external view returns (uint256);

    /// @notice Return the last recorded epoch for the system
    function getMostRecentTotalEpoch() external view returns (uint256);
}
