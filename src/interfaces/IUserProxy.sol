// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "../interfaces/ILQTYStaking.sol";

import {PermitParams} from "../utils/Types.sol";

interface IUserProxy {
    /// @notice Address of the LQTY token
    function lqty() external view returns (IERC20);
    /// @notice Address of the LUSD token
    function lusd() external view returns (IERC20);
    /// @notice Address of the V1 LQTY staking contract
    function stakingV1() external view returns (ILQTYStaking);
    /// @notice Address of the V2 LQTY staking contract
    function stakingV2() external view returns (address);

    /// @notice Stakes a given amount of LQTY tokens in the V1 staking contract
    function stake(address _from, uint256 _amount) external;
    /// @notice Stakes a given amount of LQTY tokens in the V1 staking contract using a permit
    function stakeViaPermit(address _from, uint256 _amount, PermitParams calldata _permitParams) external;
    /// @notice Unstakes a given amount of LQTY tokens from the V1 staking contract and claims the accrued rewards
    function unstake(uint256 _amount, address _lqtyRecipient, address _lusdEthRecipient)
        external
        returns (uint256 lqtyAmount, uint256 lusdAmount, uint256 ethAmount);
}
