// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockGovernance {
    function claimForInitiative(address) external pure returns (uint256) {
        return 1000e18;
    }
}
