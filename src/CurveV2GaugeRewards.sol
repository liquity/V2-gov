// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {BribeInitiative} from "./BribeInitiative.sol";

contract CurveV2GaugeRewards is BribeInitiative {
    ILiquidityGauge public immutable gauge;
    uint256 public immutable duration;

    event DepositIntoGauge(uint256 amount);

    constructor(address _governance, address _bold, address _bribeToken, address _gauge, uint256 _duration)
        BribeInitiative(_governance, _bold, _bribeToken)
    {
        gauge = ILiquidityGauge(_gauge);
        duration = _duration;
    }

    uint256 public remainder;

    /// @notice Governance transfers Bold, and we deposit it into the gauge
    /// @dev Doing this allows anyone to trigger the claim
    function onClaimForInitiative(uint16, uint256 _bold) external override onlyGovernance {
        _depositIntoGauge(_bold);
    }

    // TODO: If this is capped, we may need to donate here, so cap it here as well
    function _depositIntoGauge(uint256 amount) internal {
        uint256 total = amount + remainder;
        
        // For small donations queue them into the contract
        if (total < duration * 1000) {
            remainder += amount;
            return;
        }

        remainder = 0;

        bold.approve(address(gauge), total); 
        gauge.deposit_reward_token(address(bold), total, duration);

        emit DepositIntoGauge(total);
    }
}
