// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "./../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import "./ILQTYStaking.sol";

contract UserProxy {
    IERC20 public immutable lqty;
    IERC20 public immutable lusd;

    ILQTYStaking public immutable stakingV1;
    address public immutable stakingV2;

    address public immutable user;

    constructor(address lqty_, address lusd_, address stakingV1_, address user_) {
        lqty = IERC20(lqty_);
        lusd = IERC20(lusd_);
        stakingV1 = ILQTYStaking(stakingV1_);
        stakingV2 = msg.sender;
        user = user_;
    }

    receive() external payable {}

    modifier onlyStakingV2() {
        require(msg.sender == stakingV2, "UserProxy: caller-not-stakingV2");
        _;
    }

    function stake(uint256 amount) public onlyStakingV2 {
        lqty.transferFrom(user, address(this), amount);
        stakingV1.stake(amount);
    }

    function unstake(uint256 amount) public onlyStakingV2 {
        stakingV1.unstake(amount);

        uint256 lusdBalance = lusd.balanceOf(address(this));
        if (lusdBalance > 0) lusd.transfer(user, lusdBalance);
        uint256 lqtyBalance = lqty.balanceOf(address(this));
        if (lqtyBalance > 0) lqty.transfer(user, lqtyBalance);
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) payable(user).transfer(ethBalance);
    }
}

contract StakingV2 {
    address public immutable lqty;
    address public immutable lusd;
    address public immutable stakingV1;

    mapping(address => address) public userProxies;

    constructor(address lqty_, address lusd_, address stakingV1_) {
        lqty = lqty_;
        lusd = lusd_;
        stakingV1 = stakingV1_;
    }

    function deployUserProxy() public returns (address) {
        require(userProxies[msg.sender] == address(0), "StakingV2: proxy-exists");
        address userProxy = address(new UserProxy(lqty, lusd, stakingV1, msg.sender));

        userProxies[msg.sender] = address(userProxy);

        return userProxy;
    }

    function depositLQTY(uint256 amount) public {
        address userProxy = userProxies[msg.sender];
        require(userProxy != address(0), "StakingV2: unknown-user");

        UserProxy(payable(userProxy)).stake(amount);
    }

    function withdrawLQTY(uint256 amount) public {
        address userProxy = userProxies[msg.sender];
        require(userProxy != address(0), "StakingV2: unknown-user");

        UserProxy(payable(userProxy)).unstake(amount);
    }
}
