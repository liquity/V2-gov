// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Random} from "./Random.sol";

library UintArray {
    using Random for Random.Context;

    function seq(uint256 last) internal pure returns (uint256[] memory) {
        return seq(0, last);
    }

    function seq(uint256 first, uint256 last) internal pure returns (uint256[] memory array) {
        require(first <= last, "first > last");
        return seq(new uint256[](last - first), first);
    }

    function seq(uint256[] memory array) internal pure returns (uint256[] memory) {
        return seq(array, 0);
    }

    function seq(uint256[] memory array, uint256 first) internal pure returns (uint256[] memory) {
        for (uint256 i = 0; i < array.length; ++i) {
            array[i] = first + i;
        }

        return array;
    }

    function slice(uint256[] memory array) internal pure returns (uint256[] memory) {
        return slice(array, uint256(0), array.length);
    }

    function slice(uint256[] memory array, uint256 start) internal pure returns (uint256[] memory) {
        return slice(array, start, array.length);
    }

    function slice(uint256[] memory array, int256 start) internal pure returns (uint256[] memory) {
        return slice(array, start, array.length);
    }

    function slice(uint256[] memory array, uint256 start, int256 end) internal pure returns (uint256[] memory) {
        return slice(array, start, uint256(end < 0 ? int256(array.length) + end : end));
    }

    function slice(uint256[] memory array, int256 start, uint256 end) internal pure returns (uint256[] memory) {
        return slice(array, uint256(start < 0 ? int256(array.length) + start : start), end);
    }

    function slice(uint256[] memory array, int256 start, int256 end) internal pure returns (uint256[] memory) {
        return slice(
            array,
            uint256(start < 0 ? int256(array.length) + start : start),
            uint256(end < 0 ? int256(array.length) + end : end)
        );
    }

    function slice(uint256[] memory array, uint256 start, uint256 end) internal pure returns (uint256[] memory ret) {
        require(start <= end, "start > end");
        require(end <= array.length, "end > array.length");

        ret = new uint256[](end - start);

        for (uint256 i = start; i < end; ++i) {
            ret[i - start] = array[i];
        }
    }

    function permute(uint256[] memory array, bytes32 seed) internal pure returns (uint256[] memory) {
        return permute(array, Random.init(seed));
    }

    function permute(uint256[] memory array, Random.Context memory random) internal pure returns (uint256[] memory) {
        for (uint256 i = 0; i < array.length - 1; ++i) {
            uint256 j = random.generate(i, array.length - 1);
            (array[i], array[j]) = (array[j], array[i]);
        }

        return array;
    }
}
