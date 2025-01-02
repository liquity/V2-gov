// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

function _lqtyToVotes(uint256 _lqtyAmount, uint256 _timestamp, uint256 _offset) pure returns (uint256) {
    uint256 prod = _lqtyAmount * _timestamp;
    return prod > _offset ? prod - _offset : 0;
}
