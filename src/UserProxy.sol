// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILQTYStaking} from "./interfaces/ILQTYStaking.sol";
import {PermitParams} from "./utils/Types.sol";

contract UserProxy {
    using SafeERC20 for IERC20;

    IERC20 public immutable lqty;
    IERC20 public immutable lusd;

    ILQTYStaking public immutable stakingV1;
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

    function stake(address _from, uint256 _amount) public onlyStakingV2 {
        lqty.transferFrom(_from, address(this), _amount);
        lqty.approve(address(stakingV1), _amount);
        stakingV1.stake(_amount);
    }

    function stakeViaPermit(address _from, uint256 _amount, PermitParams calldata _permitParams) public onlyStakingV2 {
        IERC20Permit(address(lqty)).permit(
            _permitParams.owner,
            _permitParams.spender,
            _permitParams.value,
            _permitParams.deadline,
            _permitParams.v,
            _permitParams.r,
            _permitParams.s
        );
        stake(_from, _amount);
    }

    function unstake(uint256 _amount, address _lqtyRecipient, address _lusdEthRecipient)
        public
        onlyStakingV2
        returns (uint256 lqtyAmount, uint256 lusdAmount, uint256 ethAmount)
    {
        stakingV1.unstake(_amount);

        lqtyAmount = lqty.balanceOf(address(this));
        if (lqtyAmount > 0) lqty.transfer(_lqtyRecipient, lqtyAmount);
        lusdAmount = lusd.balanceOf(address(this));
        if (lusdAmount > 0) lusd.transfer(_lusdEthRecipient, lusdAmount);
        ethAmount = address(this).balance;
        if (ethAmount > 0) payable(_lusdEthRecipient).transfer(ethAmount);
    }

    receive() external payable {}
}
