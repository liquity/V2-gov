// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {BaseInitiative} from "./BaseInitiative.sol";

contract CurveV2GaugeRewards is BaseInitiative {
    ILiquidityGauge public immutable gauge;
    uint256 public immutable duration;

    constructor(address _governance, address _bold, address _bribeToken, address _gauge, uint256 _duration)
        BaseInitiative(_governance, _bold, _bribeToken)
    {
        gauge = ILiquidityGauge(_gauge);
        duration = _duration;
    }

    function depositIntoGauge() public returns (uint256) {
        uint256 amount = bold.balanceOf(address(this));
        bold.approve(address(gauge), amount);
        gauge.deposit_reward_token(address(bold), amount, duration);
        return amount;
    }

    function claimAndDepositIntoGauge() external returns (uint256) {
        governance.claimForInitiative(address(this));
        return depositIntoGauge();
    }
}
