// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./IGovernance.sol";

interface IBribeInitiative {
    event DepositBribe(address depositor, uint128 boldAmount, uint128 bribeTokenAmount, uint16 epoch);
    event ClaimBribe(address user, uint16 epoch, uint256 boldAmount, uint256 bribeTokenAmount);

    /// @notice Address of the governance contract
    function governance() external view returns (IGovernance);
    /// @notice Address of the BOLD token
    function bold() external view returns (IERC20);
    /// @notice Address of the bribe token
    function bribeToken() external view returns (IERC20);

    struct Bribe {
        uint128 boldAmount;
        uint128 bribeTokenAmount; // [scaled as 10 ** bribeToken.decimals()]
    }

    /// @notice Amount of bribe tokens deposited for a given epoch
    function bribeByEpoch(uint16 _epoch) external view returns (uint128, uint128);
    /// @notice Check if a user has claimed bribes for a given epoch
    function claimedBribeAtEpoch(address _user, uint16 _epoch) external view returns (bool);

    /// @notice Total LQTY allocated to the initiative at a given epoch
    function totalLQTYAllocatedByEpoch(uint16 _epoch) external view returns (uint96);
    /// @notice LQTY allocated by a user to the initiative at a given epoch
    function lqtyAllocatedByUserAtEpoch(address _user, uint16 _epoch) external view returns (uint96);

    /// @notice Deposit bribe tokens for a given epoch
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint16 _epoch) external;
    /// @notice Claim bribes for a user
    function claimBribes(
        address _user,
        uint16[] calldata _epochs,
        uint16[] calldata _prevLQTYAllocationEpochs,
        uint16[] calldata _prevTotalLQTYAllocationEpochs
    ) external returns (uint256 boldAmount, uint256 bribeTokenAmount);
}
