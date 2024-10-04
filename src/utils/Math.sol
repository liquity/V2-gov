// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function add(uint88 a, int96 b) pure returns (uint88) {
    if (b < 0) {
        return uint88(a - uint88(uint96(-b)));
    }
    return uint88(a + uint88(uint96(b)));
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

function abs(int96 a) pure returns (uint96) {
    return a < 0 ? uint96(-a) : uint96(a);
}
