// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function add(uint88 a, int88 b) pure returns (uint88) {
    if (b < 0) {
        return a - abs(b);
    }
    return a + abs(b);
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}

function abs(int88 a) pure returns (uint88) {
    return a < 0 ? uint88(uint256(-int256(a))) : uint88(a);
}
