// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

function add(uint256 a, int256 b) pure returns (uint120) {
    if (b < 0) {
        return uint120(a - uint256(-b));
    }
    return uint120(a + uint256(b));
}

function _add(uint96 a, int192 b) pure returns (uint96) {
    if (b < 0) {
        return uint96(a - uint96(uint192(-b)));
    }
    return uint96(a + uint96(uint192(b)));
}

function sub(uint256 a, int256 b) pure returns (uint128) {
    if (b < 0) {
        return uint128(a + uint256(-b));
    }
    return uint128(a - uint256(b));
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}
