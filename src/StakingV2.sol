// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";
import {ILQTYStaking} from "./ILQTYStaking.sol";
import {Voting} from "./Voting.sol";

uint256 constant WAD = 1e18;
uint256 constant ONE_YEAR = 31_536_000;

contract StakingV2 is UserProxyFactory {
    uint256 public immutable deploymentTimestamp;
    Voting public voting;

    uint256 public totalShares;
    mapping(address => uint256) public sharesByUser;

    constructor(address lqty_, address lusd_, address stakingV1_) UserProxyFactory(lqty_, lusd_, stakingV1_) {
        deploymentTimestamp = block.timestamp;
    }

    function setVoting(address voting_) external {
        require(address(voting) == address(0), "StakingV2: voting-already-set");
        voting = Voting(voting_);
    }

    function currentShareRate() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) * WAD / ONE_YEAR) + WAD;
    }

    function depositLQTY(uint256 lqtyAmount) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        userProxy.stake(msg.sender, lqtyAmount);

        uint256 shareAmount = lqtyAmount * WAD / currentShareRate();
        sharesByUser[msg.sender] += shareAmount;

        return shareAmount;
    }

    function withdrawShares(uint256 shareAmount) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 shares = sharesByUser[msg.sender];

        // check if user has enough unallocated shares
        require(
            shareAmount <= shares - (voting.votesAllocatedByUser(msg.sender) * WAD / currentShareRate()),
            "StakingV2: insufficient-unallocated-shares"
        );

        uint256 lqtyAmount = (ILQTYStaking(userProxy.stakingV1()).stakes(address(userProxy)) * shareAmount) / shares;
        userProxy.unstake(msg.sender, lqtyAmount);

        sharesByUser[msg.sender] = shares - shareAmount;

        return lqtyAmount;
    }

    // Claim staking rewards from StakingV1 without unstaking
    function claimFromStakingV1() external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(msg.sender, 0);
    }
}
