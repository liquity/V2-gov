// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";
import {ILQTYStaking} from "./ILQTYStaking.sol";
import {Voting} from "./Voting.sol";
import {WAD, ONE_YEAR, PermitParams} from "./Utils.sol";

// @title StakingV2
// @notice This contract allows users to stake their LQTY in return for receiving shares which can be used to vote
// on initiatives proposed in the Voting contract. The deposited LQTY is staked in LQRTYStaking (v1 staking) to earn
// additional LUSD and ETH rewards via the UserProxy contract which is deployed for each user.
contract StakingV2 is UserProxyFactory {
    uint256 public immutable deploymentTimestamp;
    Voting public immutable voting;

    // Total shares in circulation
    uint256 public totalShares;
    // Mapping of each user's share balance
    mapping(address => uint256) public sharesByUser;

    constructor(address _lqty, address _lusd, address _stakingV1, address _voting)
        UserProxyFactory(_lqty, _lusd, _stakingV1)
    {
        deploymentTimestamp = block.timestamp;
        voting = Voting(_voting);
    }

    // Returns the current share rate based on the time since deployment
    function currentShareRate() public view returns (uint256) {
        return ((block.timestamp - deploymentTimestamp) * WAD / ONE_YEAR) + WAD;
    }

    function _mintShares(uint256 _lqtyAmount) private returns (uint256) {
        uint256 shareAmount = _lqtyAmount * WAD / currentShareRate();
        sharesByUser[msg.sender] += shareAmount;
        return shareAmount;
    }

    // Deposits LQTY and mints shares based on the current share rate
    function depositLQTY(uint256 _lqtyAmount) external returns (uint256) {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).stake(msg.sender, _lqtyAmount);
        return _mintShares(_lqtyAmount);
    }

    // Deposits LQTY via Permit and mints shares based on the current share rate
    function depositLQTYViaPermit(uint256 _lqtyAmount, PermitParams calldata _permitParams)
        external
        returns (uint256)
    {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).stakeViaPermit(msg.sender, _lqtyAmount, _permitParams);
        return _mintShares(_lqtyAmount);
    }

    // Withdraws LQRT by burning the shares and claim any accrued LUSD and ETH rewards from StakingV1
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

    // Claims staking rewards from StakingV1 without unstaking
    function claimFromStakingV1() external {
        UserProxy(payable(deriveUserProxyAddress(msg.sender))).unstake(msg.sender, 0);
    }
}
