// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

function add(uint256 a, int256 b) pure returns (uint128) {
    if (b < 0) {
        return uint128(a - uint256(-b));
    }
    return uint128(a + uint256(b));
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}
