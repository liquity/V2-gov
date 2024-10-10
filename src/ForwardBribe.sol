// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BribeInitiative} from "./BribeInitiative.sol";

contract ForwardBribe is BribeInitiative {
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
