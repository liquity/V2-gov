// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {ILQTYStaking} from "../interfaces/ILQTYStaking.sol";

import {PermitParams} from "../utils/Types.sol";

interface IUserProxy {
    /// @notice Address of the LQTY token
    /// @return lqty Address of the LQTY token
    function lqty() external view returns (IERC20 lqty);
    /// @notice Address of the LUSD token
    /// @return lusd Address of the LUSD token
    function lusd() external view returns (IERC20 lusd);
    /// @notice Address of the V1 LQTY staking contract
    /// @return stakingV1 Address of the V1 LQTY staking contract
    function stakingV1() external view returns (ILQTYStaking stakingV1);
    /// @notice Address of the V2 LQTY staking contract
    /// @return stakingV2 Address of the V2 LQTY staking contract
    function stakingV2() external view returns (address stakingV2);

    /// @notice Stakes a given amount of LQTY tokens in the V1 staking contract
    /// @dev The LQTY tokens must be approved for transfer by the user
    /// @param _amount Amount of LQTY tokens to stake
    /// @param _lqtyFrom Address from which to transfer the LQTY tokens
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    /// @return lusdReceived Amount of LUSD tokens received as a side-effect of staking new LQTY
    /// @return lusdSent Amount of LUSD tokens sent to `_recipient` (may include previously received LUSD)
    /// @return ethReceived Amount of ETH received as a side-effect of staking new LQTY
    /// @return ethSent Amount of ETH sent to `_recipient` (may include previously received ETH)
    function stake(uint256 _amount, address _lqtyFrom, bool _doSendRewards, address _recipient)
        external
        returns (uint256 lusdReceived, uint256 lusdSent, uint256 ethReceived, uint256 ethSent);

    /// @notice Stakes a given amount of LQTY tokens in the V1 staking contract using a permit
    /// @param _amount Amount of LQTY tokens to stake
    /// @param _lqtyFrom Address from which to transfer the LQTY tokens
    /// @param _permitParams Parameters for the permit data
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    /// @return lusdReceived Amount of LUSD tokens received as a side-effect of staking new LQTY
    /// @return lusdSent Amount of LUSD tokens sent to `_recipient` (may include previously received LUSD)
    /// @return ethReceived Amount of ETH received as a side-effect of staking new LQTY
    /// @return ethSent Amount of ETH sent to `_recipient` (may include previously received ETH)
    function stakeViaPermit(
        uint256 _amount,
        address _lqtyFrom,
        PermitParams calldata _permitParams,
        bool _doSendRewards,
        address _recipient
    ) external returns (uint256 lusdReceived, uint256 lusdSent, uint256 ethReceived, uint256 ethSent);

    /// @notice Unstakes a given amount of LQTY tokens from the V1 staking contract and claims the accrued rewards
    /// @param _amount Amount of LQTY tokens to unstake
    /// @param _doSendRewards If true, send rewards claimed from LQTY staking
    /// @param _recipient Address to which the tokens should be sent
    /// @return lqtyReceived Amount of LQTY tokens actually unstaked (may be lower than `_amount`)
    /// @return lqtySent Amount of LQTY tokens sent to `_recipient` (may include LQTY sent to the proxy from sources other than V1 staking)
    /// @return lusdReceived Amount of LUSD tokens received as a side-effect of staking new LQTY
    /// @return lusdSent Amount of LUSD tokens claimed (may include previously received LUSD)
    /// @return ethReceived Amount of ETH received as a side-effect of staking new LQTY
    /// @return ethSent Amount of ETH claimed (may include previously received ETH)
    function unstake(uint256 _amount, bool _doSendRewards, address _recipient)
        external
        returns (
            uint256 lqtyReceived,
            uint256 lqtySent,
            uint256 lusdReceived,
            uint256 lusdSent,
            uint256 ethReceived,
            uint256 ethSent
        );

    /// @notice Returns the current amount LQTY staked by a user in the V1 staking contract
    /// @return staked Amount of LQTY tokens staked
    function staked() external view returns (uint256);
}
