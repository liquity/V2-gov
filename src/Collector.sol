// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/// @title BOLD Collector
/// @notice This contract accrues BOLD over time which Voting can draw from
contract Collector {
    IERC20 public bold;
    address public voting;

    constructor(address _bold, address _voting) {
        bold = IERC20(_bold);
        voting = _voting;
        approveVoting();
    }

    // Approve Voting contract to transfer BOLD tokens
    function approveVoting() public {
        bold.approve(voting, type(uint256).max);
    }
}
