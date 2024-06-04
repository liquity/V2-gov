// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Clones} from "./../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

import {UserProxy} from "./UserProxy.sol";

contract UserProxyFactory {
    address public immutable userProxyImplementation;

    constructor(address lqty, address lusd, address stakingV1) {
        userProxyImplementation = address(new UserProxy(lqty, lusd, stakingV1));
    }

    function userProxyCreationCode() public pure returns (bytes memory) {
        return type(UserProxy).creationCode;
    }

    function deriveUserProxyAddress(address user) public view returns (address) {
        return Clones.predictDeterministicAddress(userProxyImplementation, bytes32(uint256(uint160(user))));
    }

    function deployUserProxy() public returns (address) {
        // reverts if the user already has a proxy
        return Clones.cloneDeterministic(userProxyImplementation, bytes32(uint256(uint160(msg.sender))));
    }
}
