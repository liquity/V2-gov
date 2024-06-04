// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ILQTYStaking.sol";

contract UserProxy {
    ILQTYStaking public immutable stakingV1;
    address public immutable stakingV2;
    address public immutable user;

    constructor(address stakingV1_, address user_) {
        stakingV1 = ILQTYStaking(stakingV1_);
        stakingV2 = msg.sender;
        user = user_;
    }

    modifier onlyStakingV2() {
        require(msg.sender == stakingV2, "UserProxy: caller-not-stakingV2");
        _;
    }

    modifier onlyUser() {
        require(msg.sender == user, "UserProxy: caller-not-user");
        _;
    }

    function stake(uint256 amount) public onlyStakingV2 {
        stakingV1.stake(amount);
    }

    function unstake(uint256 amount) public onlyStakingV2 {
        stakingV1.unstake(amount);
    }

    function claimRewards() public onlyStakingV2() {
        // stakingV1.claimRewards();
    }
}

contract StakingV2 {
    address public immutable stakingV1;

    mapping(address => address) public userProxies;

    constructor(address stakingV1_) {
        stakingV1 = stakingV1_;
    }

    function depositLQTY(uint256 amount) public {
        address userProxy = userProxies[msg.sender];
        if (userProxy == address(0)) {
            userProxy = address(new UserProxy(stakingV1, msg.sender));
            userProxies[msg.sender] = address(userProxy);
        }

        UserProxy(userProxy).stake(amount);
    }

    function withdrawLQTY(uint256 amount) public {
        address userProxy = userProxies[msg.sender];
        require(userProxy != address(0), "StakingV2: unknown-user");

        UserProxy(userProxy).unstake(amount);
    }
}
