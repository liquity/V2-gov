// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Checks that there's no duplicate addresses
/// @param arr - List to check for dups
function _requireNoDuplicates(address[] calldata arr) pure {
    uint256 arrLength = arr.length;
    if (arrLength == 0) return;

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

function _requireNoNegatives(int256[] memory vals) pure {
    uint256 arrLength = vals.length;

    for (uint i; i < arrLength; i++) {
        require(vals[i] >= 0, "Cannot be negative");
    }
}
