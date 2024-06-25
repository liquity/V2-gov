// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

contract CurveV2GaugeRewards {
    IGovernance public immutable governance;
    IERC20 public immutable bold;
    ILiquidityGauge public immutable gauge;
    uint256 public immutable duration;

    constructor(address _governance, address _bold, address _gauge, uint256 _duration) {
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
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
