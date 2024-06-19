// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
uint256 constant ONE_YEAR = 31_536_000;
