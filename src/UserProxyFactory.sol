// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Clones} from "openzeppelin/contracts/proxy/Clones.sol";

import {IUserProxyFactory} from "./interfaces/IUserProxyFactory.sol";
import {UserProxy} from "./UserProxy.sol";

contract UserProxyFactory is IUserProxyFactory {
    /// @inheritdoc IUserProxyFactory
    address public immutable userProxyImplementation;

    constructor(address _lqty, address _lusd, address _stakingV1) {
        userProxyImplementation = address(new UserProxy(_lqty, _lusd, _stakingV1));
    }

    /// @inheritdoc IUserProxyFactory
    function deriveUserProxyAddress(address _user) public view returns (address) {
        return Clones.predictDeterministicAddress(userProxyImplementation, bytes32(uint256(uint160(_user))));
    }

    /// @inheritdoc IUserProxyFactory
    function deployUserProxy() public returns (address) {
        // reverts if the user already has a proxy
        address userProxy = Clones.cloneDeterministic(userProxyImplementation, bytes32(uint256(uint160(msg.sender))));

        emit DeployUserProxy(msg.sender, userProxy);

        return userProxy;
    }
}
