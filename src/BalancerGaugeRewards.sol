// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {BribeInitiative} from "./BribeInitiative.sol";

contract BalancerGaugeRewards is BribeInitiative {
    ILiquidityGauge public immutable gauge;
    uint256 public immutable duration;

    event DepositIntoGauge(uint256 amount);

    constructor(address _governance, address _bold, address _bribeToken, address _gauge, uint256 _duration)
        BribeInitiative(_governance, _bold, _bribeToken)
    {
        gauge = ILiquidityGauge(_gauge);
        duration = _duration;
    }

    /// @notice Governance transfers Bold, and we deposit it into the gauge
    /// @dev Doing this allows anyone to trigger the claim
    function onClaimForInitiative(uint256, uint256 boldAmount) external override onlyGovernance {
        _depositIntoGauge(boldAmount);
    }

    function _depositIntoGauge(uint256 amount) internal {
        uint256 available = bold.balanceOf(address(this));
        if (available < amount) {
            amount = available; // Cap due to rounding error causing a bit more bold being given away
        }

        bold.approve(address(gauge), amount);
        gauge.deposit_reward_token(address(bold), amount);

        emit DepositIntoGauge(amount);
    }
}
