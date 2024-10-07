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

    function depositIntoGauge() external returns (uint256) {
        // Claim rewards (could be front-run)
        governance.claimForInitiative(address(this));

        // Use available balance
        uint256 amount = bold.balanceOf(address(this));

        bold.approve(address(gauge), amount);
        gauge.deposit_reward_token(address(bold), amount, duration);

        emit DepositIntoGauge(amount);

        return amount;
    }
}
