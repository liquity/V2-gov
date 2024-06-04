// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "./../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "./ILQTYStaking.sol";

contract UserProxy {
    IERC20 public immutable lqty;
    IERC20 public immutable lusd;

    ILQTYStaking public immutable stakingV1;
    address public immutable stakingV2;

    constructor(address lqty_, address lusd_, address stakingV1_) {
        lqty = IERC20(lqty_);
        lusd = IERC20(lusd_);
        stakingV1 = ILQTYStaking(stakingV1_);
        stakingV2 = msg.sender;
    }

    modifier onlyStakingV2() {
        require(msg.sender == stakingV2, "UserProxy: caller-not-stakingV2");
        _;
    }

    function stake(address user, uint256 amount) public onlyStakingV2 {
        lqty.transferFrom(user, address(this), amount);
        stakingV1.stake(amount);
    }

    function unstake(address user, uint256 amount) public onlyStakingV2 {
        stakingV1.unstake(amount);

        uint256 lqtyBalance = lqty.balanceOf(address(this));
        if (lqtyBalance > 0) lqty.transfer(user, lqtyBalance);
        uint256 lusdBalance = lusd.balanceOf(address(this));
        if (lusdBalance > 0) lusd.transfer(user, lusdBalance);
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) payable(user).transfer(ethBalance);
    }

    receive() external payable {}
}
