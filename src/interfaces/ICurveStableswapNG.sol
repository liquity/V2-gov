// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICurveStableswapNG {
    function add_liquidity(uint256[] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

    function deposit_reward_token(address _reward_token, uint256 _amount, uint256 _epoch) external;
}
