// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IUserProxyFactory {
    event DeployUserProxy(address indexed user, address indexed userProxy);

    /// @notice Address of the UserProxy implementation contract
    function userProxyImplementation() external view returns (address);

    /// @notice Derive the address of a user's proxy contract
    function deriveUserProxyAddress(address _user) external view returns (address);

    /// @notice Deploy a new UserProxy contract for the sender
    function deployUserProxy() external returns (address);
}
