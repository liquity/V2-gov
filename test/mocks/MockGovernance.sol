// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockGovernance {
    uint16 private __epoch;

    function claimForInitiative(address) external pure returns (uint256) {
        return 1000e18;
    }

    function setEpoch(uint16 _epoch) external {
        __epoch = _epoch;
    }

    function epoch() external view returns (uint16) {
        return __epoch;
    }
}
