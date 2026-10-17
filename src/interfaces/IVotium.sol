// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVotium {
    // Deposit vote incentive for a single gauge in a active round with no max and no exclusions -- for gas efficiency
    function depositIncentiveSimple(address _token, uint256 _amount, address _gauge) external;
}
