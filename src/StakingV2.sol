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
    Voting public immutable voting;

    uint256 public totalShares;
    mapping(address => uint256) public sharesByUser;

    constructor(address _lqty, address _lusd, address _stakingV1, address _voting)
        UserProxyFactory(_lqty, _lusd, _stakingV1)
    {
        deploymentTimestamp = block.timestamp;
        voting = Voting(_voting);
    }

    function currentShareRate() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) * WAD / ONE_YEAR) + WAD;
    }

    function depositLQTY(uint256 _lqtyAmount) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        userProxy.stake(msg.sender, _lqtyAmount);

        uint256 shareAmount = _lqtyAmount * WAD / currentShareRate();
        sharesByUser[msg.sender] += shareAmount;

        return shareAmount;
    }

    function withdrawShares(uint256 _shareAmount) external returns (uint256) {
        UserProxy userProxy = UserProxy(payable(deriveUserProxyAddress(msg.sender)));
        uint256 shares = sharesByUser[msg.sender];

        // check if user has enough unallocated shares
        require(
            _shareAmount <= shares - voting.sharesAllocatedByUser(msg.sender),
            "StakingV2: insufficient-unallocated-shares"
        );

        uint256 lqtyAmount = (ILQTYStaking(userProxy.stakingV1()).stakes(address(userProxy)) * _shareAmount) / shares;
        userProxy.unstake(msg.sender, lqtyAmount);

        sharesByUser[msg.sender] = shares - _shareAmount;

        return lqtyAmount;
    }

    // Claim staking rewards from StakingV1 without unstaking
    function claimFromStakingV1() external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(msg.sender, 0);
    }
}
