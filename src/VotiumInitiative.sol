// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVotium} from "./interfaces/IVotium.sol";

import {BribeInitiative} from "./BribeInitiative.sol";

contract VotiumInitiative is BribeInitiative {
    IVotium public immutable votium;
    address public immutable gauge;
    uint256 public immutable duration;

    event DepositIntoVotium(uint256 amount);

    constructor(
        address _governance,
        address _bold,
        address _bribeToken,
        address _votium,
        address _gauge,
        uint256 _duration
    ) BribeInitiative(_governance, _bold, _bribeToken) {
        votium = IVotium(_votium);
        gauge = _gauge;
        duration = _duration;
    }

    uint256 public remainder;

    /// @notice Governance transfers Bold, and we deposit it into the gauge
    /// @dev Doing this allows anyone to trigger the claim
    function onClaimForInitiative(uint256, uint256) external override onlyGovernance {
        _depositIntoVotium();
    }

    function _depositIntoVotium() internal {
        uint256 total = bold.balanceOf(address(this));

        // For small donations queue them into the contract
        if (total < duration * 1000) {
            return;
        }

        bold.approve(address(votium), total);
        votium.depositIncentiveSimple(address(bold), total, gauge);

        emit DepositIntoVotium(total);
    }
}
