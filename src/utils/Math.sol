// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// TODO: Needs to be checked
function add(uint88 a, int96 b) pure returns (uint88) {
    // Checked addition of a and b
    int96 temp = int96(uint96(a)) + b;

    // if result is negative, we must throw
    require(temp >= 0);
    // Result must fit in a u88
    require(uint96(temp) < type(uint88).max);

    
    // Safe cast
    return (uint88(uint96(temp)));
}




function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}

function abs(int96 a) pure returns (uint96) {
    return a < 0 ? uint96(-a) : uint96(a);
}
