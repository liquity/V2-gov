// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract MockStakingV1 {
    IERC20 public immutable lqty;

    mapping(address => uint256) public stakes;

    constructor(address _lqty) {
        lqty = IERC20(_lqty);
    }

    function stake(uint256 _LQTYamount) external {
        stakes[msg.sender] += _LQTYamount;
        lqty.transferFrom(msg.sender, address(this), _LQTYamount);
    }

    function unstake(uint256 _LQTYamount) external {
        stakes[msg.sender] -= _LQTYamount;
        lqty.transfer(msg.sender, _LQTYamount);
    }
}
