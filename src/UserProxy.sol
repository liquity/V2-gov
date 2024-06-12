// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "./../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "./ILQTYStaking.sol";

contract UserProxy {
    IERC20 public immutable lqty;
    IERC20 public immutable lusd;

    ILQTYStaking public immutable stakingV1;
    address public immutable stakingV2;

    constructor(address _lqty, address _lusd, address _stakingV1) {
        lqty = IERC20(_lqty);
        lusd = IERC20(_lusd);
        stakingV1 = ILQTYStaking(_stakingV1);
        stakingV2 = msg.sender;
    }

    modifier onlyStakingV2() {
        require(msg.sender == stakingV2, "UserProxy: caller-not-stakingV2");
        _;
    }

    function stake(address _user, uint256 _amount) public onlyStakingV2 {
        lqty.transferFrom(_user, address(this), _amount);
        stakingV1.stake(_amount);
    }

    function unstake(address _user, uint256 _amount) public onlyStakingV2 {
        stakingV1.unstake(_amount);

        uint256 lqtyBalance = lqty.balanceOf(address(this));
        if (lqtyBalance > 0) lqty.transfer(_user, lqtyBalance);
        uint256 lusdBalance = lusd.balanceOf(address(this));
        if (lusdBalance > 0) lusd.transfer(_user, lusdBalance);
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) payable(_user).transfer(ethBalance);
    }

    receive() external payable {}
}
