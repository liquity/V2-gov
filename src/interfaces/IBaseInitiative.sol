// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./IGovernance.sol";

interface IBaseInitiative {
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

    /// @notice Epoch at which the user last allocated shares to the initiative
    function allocatedAtEpoch(address) external view returns (uint16);
    /// @notice Amount of bribe tokens deposited for a given epoch
    function bribeByEpoch(uint256) external view returns (uint128, uint128);

    /// @notice Deposit bribe tokens for a given epoch
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint256 _epoch) external;
    /// @notice Claim bribes for a user
    function claimBribes(address _user) external returns (uint256, uint256);
}
