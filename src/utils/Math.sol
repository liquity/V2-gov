// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function add(uint256 a, int256 b) pure returns (uint256) {
    if (b < 0) {
        return a - abs(b);
    }
    return a + uint256(b);
}

function sub(uint256 a, int256 b) pure returns (uint256) {
    if (b < 0) {
        return a + abs(b);
    }
    return a - uint256(b);
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}

function abs(int256 a) pure returns (uint256) {
    return a < 0 ? uint256(-int256(a)) : uint256(a);
}
