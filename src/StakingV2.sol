// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UserProxy} from "./UserProxy.sol";
import {UserProxyFactory} from "./UserProxyFactory.sol";

contract StakingV2 is UserProxyFactory {
    constructor(address lqty_, address lusd_, address stakingV1_) UserProxyFactory(lqty_, lusd_, stakingV1_) {}

    function deployUserProxy() public returns (address) {
        return _deployUserProxy();
    }

    function depositLQTY(uint256 amount) public {
        address userProxy = deriveUserProxyAddress(msg.sender);
        UserProxy(payable(userProxy)).stake(msg.sender, amount);
    }

    function withdrawLQTY(uint256 amount) public {
        address userProxy = deriveUserProxyAddress(msg.sender);
        UserProxy(payable(userProxy)).unstake(msg.sender, amount);
    }
}
