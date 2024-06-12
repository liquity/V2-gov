// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract Collector {
    IERC20 public bold;
    address public voting;

    constructor(address _bold, address _voting) {
        bold = IERC20(_bold);
        voting = _voting;
        approveVoting();
    }

    function approveVoting() public {
        bold.approve(voting, type(uint256).max);
    }
}
