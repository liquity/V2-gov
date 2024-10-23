// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Checks that there's no duplicate addresses
/// @param arr - List to check for dups
function _requireNoDuplicates(address[] memory arr) pure {
    uint256 arrLength = arr.length;
    // only up to len - 1 (no j to check if i == len - 1)
    for (uint i; i < arrLength - 1;) {
        for (uint j = i + 1; j < arrLength;) {
            require(arr[i] != arr[j], "dup");

            unchecked {
                ++j;
            }
        }

        unchecked {
            ++i;
        }
    }
}
