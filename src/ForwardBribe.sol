// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BribeInitiative} from "./BribeInitiative.sol";

contract ForwardBribe is BribeInitiative {
    using SafeERC20 for IERC20;

    address public immutable receiver;

    constructor(address _governance, address _bold, address _bribeToken, address _receiver)
        BribeInitiative(_governance, _bold, _bribeToken)
    {
        receiver = _receiver;
    }

    function forwardBribe() external {
        governance.claimForInitiative(address(this));

        uint boldAmount = bold.balanceOf(address(this));
        uint bribeTokenAmount = bribeToken.balanceOf(address(this));

        if (boldAmount != 0) bold.transfer(receiver, boldAmount);
        if (bribeTokenAmount != 0) bribeToken.transfer(receiver, bribeTokenAmount);
    }
}
