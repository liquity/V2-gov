// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Clones} from "./../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

import {UserProxy} from "./UserProxy.sol";

contract UserProxyFactory {
    address public immutable userProxyImplementation;

    constructor(address _lqty, address _lusd, address _stakingV1) {
        userProxyImplementation = address(new UserProxy(_lqty, _lusd, _stakingV1));
    }

    function deriveUserProxyAddress(address _user) public view returns (address) {
        return Clones.predictDeterministicAddress(userProxyImplementation, bytes32(uint256(uint160(_user))));
    }

    function deployUserProxy() external returns (address) {
        // reverts if the user already has a proxy
        return Clones.cloneDeterministic(userProxyImplementation, bytes32(uint256(uint160(msg.sender))));
    }
}
