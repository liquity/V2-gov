// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct PermitParams {
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

uint256 constant WAD = 1e18;
