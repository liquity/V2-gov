// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUserProxy} from "./interfaces/IUserProxy.sol";
import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";
import {PermitParams} from "./utils/Types.sol";

contract UserProxy is IUserProxy {
    using SafeERC20 for IERC20;

    /// @inheritdoc IUserProxy
    IERC20 public immutable lqty;
    /// @inheritdoc IUserProxy
    IERC20 public immutable lusd;

    /// @inheritdoc IUserProxy
    ILQTYStaking public immutable stakingV1;
    /// @inheritdoc IUserProxy
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

    /// @inheritdoc IUserProxy
    function stake(uint256 _amount, address _lqtyFrom) public onlyStakingV2 {
        lqty.safeTransferFrom(_lqtyFrom, address(this), _amount);
        lqty.approve(address(stakingV1), _amount);
        stakingV1.stake(_amount);
        emit Stake(_amount, _lqtyFrom);
    }

    /// @inheritdoc IUserProxy
    function stakeViaPermit(uint256 _amount, address _lqtyFrom, PermitParams calldata _permitParams)
        public
        onlyStakingV2
    {
        require(_lqtyFrom == _permitParams.owner, "UserProxy: owner-not-sender");
        try IERC20Permit(address(lqty)).permit(
            _permitParams.owner,
            _permitParams.spender,
            _permitParams.value,
            _permitParams.deadline,
            _permitParams.v,
            _permitParams.r,
            _permitParams.s
        ) {} catch {}
        stake(_amount, _lqtyFrom);
    }

    /// @inheritdoc IUserProxy
    function unstake(uint256 _amount, address _recipient)
        public
        onlyStakingV2
        returns (uint256 lusdAmount, uint256 ethAmount)
    {
        stakingV1.unstake(_amount);

        uint256 lqtyAmount = lqty.balanceOf(address(this));
        if (lqtyAmount > 0) lqty.safeTransfer(_recipient, lqtyAmount);
        lusdAmount = lusd.balanceOf(address(this));
        if (lusdAmount > 0) lusd.safeTransfer(_recipient, lusdAmount);
        ethAmount = address(this).balance;
        if (ethAmount > 0) {
            (bool success,) = payable(_recipient).call{value: ethAmount}("");
            require(success, "UserProxy: eth-fail");
        }

        emit Unstake(_amount, _recipient, lusdAmount, ethAmount);
    }

    /// @inheritdoc IUserProxy
    function staked() external view returns (uint88) {
        return uint88(stakingV1.stakes(address(this)));
    }

    receive() external payable {}
}
