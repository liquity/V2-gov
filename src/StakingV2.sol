// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";
import {ILQTYStaking} from "./ILQTYStaking.sol";

uint256 constant WAD = 1e18;
uint256 constant ONE_YEAR = 31_536_000;

contract StakingV2 is UserProxyFactory {
    uint256 public immutable deploymentTimestamp;

    uint256 public totalShares;
    mapping(address => uint256) public sharesByUser;
    mapping(address => uint256) public lqtyByUser;

    constructor(address lqty_, address lusd_, address stakingV1_) UserProxyFactory(lqty_, lusd_, stakingV1_) {
        deploymentTimestamp = block.timestamp;
    }

    function currentShareRate() public view returns (uint256) {
        // share exchange rate increases at a simple rate of 1000% per year since deployment, it is quoted on a 10^12 basis
        return ((block.timestamp - deploymentTimestamp) * WAD / ONE_YEAR) + WAD;
    }

    // Voting power statically increases over time starting from 0 at time of share issuance
    function votingPower(address user) public view returns (uint256) {
        uint256 shares = sharesByUser[user];
        uint256 weightedShares = shares * currentShareRate();
        return (weightedShares - (shares * WAD)) / WAD;
    }

    function depositLQTY(uint256 lqtyAmount) public returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        userProxy.stake(msg.sender, lqtyAmount);

        uint256 shareAmount = lqtyAmount * WAD / currentShareRate();
        sharesByUser[msg.sender] += shareAmount;

        return shareAmount;
    }

    function withdrawShares(uint256 shareAmount) public returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 totalLqty = ILQTYStaking(userProxy.stakingV1()).stakes(address(userProxy));

        uint256 shares = sharesByUser[msg.sender];
        uint256 lqtyAmount = (totalLqty * shareAmount) / shares;
        userProxy.unstake(msg.sender, lqtyAmount);

        sharesByUser[msg.sender] = shares - shareAmount;

        return lqtyAmount;
    }

    // Claim staking rewards from StakingV1 without unstaking
    function claimFromStakingV1() public {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(msg.sender, 0);
    }
}
