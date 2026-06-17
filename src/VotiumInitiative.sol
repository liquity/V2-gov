// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVotium} from "./interfaces/IVotium.sol";

import {BribeInitiative} from "./BribeInitiative.sol";

contract VotiumInitiative is BribeInitiative {
    IVotium public immutable votium;
    address public immutable gauge;
    uint256 public immutable duration;

    uint256 public remainder;

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

    /// @notice Governance transfers Bold, and we deposit it into the gauge
    /// @dev Doing this allows anyone to trigger the claim
    function onClaimForInitiative(uint256, uint256 _bold) external override onlyGovernance {
        _depositIntoVotium(_bold);
    }

    function _depositIntoVotium(uint256 _amount) internal {
        uint256 total = _amount + remainder;

        // For small donations queue them into the contract
        if (total < duration * 1000) {
            remainder += _amount;
            return;
        }

        remainder = 0;

        uint256 available = bold.balanceOf(address(this));
        if (available < total) {
            total = available; // Cap due to rounding error causing a bit more bold being given away
        }

        bold.approve(address(votium), total);
        votium.depositIncentiveSimple(address(bold), total, gauge);

        emit DepositIntoVotium(total);
    }
}
