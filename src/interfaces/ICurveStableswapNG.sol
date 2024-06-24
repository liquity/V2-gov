// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICurveStableswapNG {

    function add_liquidity(uint256[] calldata _amounts,uint256 _min_mint_amount) external returns (uint256);
}