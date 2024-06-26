// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILiquidityGauge {
    function add_reward(address _reward_token, address _distributor) external;

    function deposit_reward_token(address _reward_token, uint256 _amount, uint256 _epoch) external;
}
