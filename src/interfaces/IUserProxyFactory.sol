// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUserProxyFactory {
    event DeployUserProxy(address indexed user, address indexed userProxy);

    /// @notice Address of the UserProxy implementation contract
    /// @return implementation Address of the UserProxy implementation contract
    function userProxyImplementation() external view returns (address implementation);

    /// @notice Derive the address of a user's proxy contract
    /// @param _user Address of the user
    /// @return userProxyAddress Address of the user's proxy contract
    function deriveUserProxyAddress(address _user) external view returns (address userProxyAddress);

    /// @notice Deploy a new UserProxy contract for the sender
    /// @return userProxyAddress Address of the deployed UserProxy contract
    function deployUserProxy() external returns (address userProxyAddress);
}
