// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function bound(uint256 x, uint256 min, uint256 max) pure returns (uint256) {
    require(min <= max, "min > max");
    return min == 0 && max == type(uint256).max ? x : min + x % (max - min + 1);
}

library Random {
    struct Context {
        bytes32 seed;
    }

    function init(bytes32 seed) internal pure returns (Random.Context memory c) {
        init(c, seed);
    }

    function init(Context memory c, bytes32 seed) internal pure {
        c.seed = seed;
    }

    function generate(Context memory c) internal pure returns (uint256) {
        return generate(c, 0, type(uint256).max);
    }

    function generate(Context memory c, uint256 max) internal pure returns (uint256) {
        return generate(c, 0, max);
    }

    function generate(Context memory c, uint256 min, uint256 max) internal pure returns (uint256) {
        c.seed = keccak256(abi.encode(c.seed));
        return bound(uint256(c.seed), min, max);
    }
}
