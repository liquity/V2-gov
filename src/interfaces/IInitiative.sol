// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IInitiative {
    /// @notice Callback hook that is called by Governance after the initiative was successfully registered
    function onRegisterInitiative() external;

    /// @notice Callback hook that is called by Governance after the initiative was unregistered
    function onUnregisterInitiative() external;

    /// @notice Callback hook that is called by Governance after the share allocation is updated by a user
    /// @param _user Address of the user that updated their share allocation
    /// @param _shares Allocated shares
    /// @param _vetoShares Allocated veto shares
    function onAfterAllocateShares(address _user, uint128 _shares, uint128 _vetoShares) external;

    /// @notice Callback hook that is called by Governance after the claim for the last epoch was distributed
    /// to the initiative
    /// @param _bold Amount of BOLD that was distributed
    function onClaimForInitiative(uint256 _bold) external;
}
