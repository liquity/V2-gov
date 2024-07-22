// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IInitiative {
    /// @notice Callback hook that is called by Governance after the initiative was successfully registered
    function onRegisterInitiative() external;

    /// @notice Callback hook that is called by Governance after the initiative was unregistered
    function onUnregisterInitiative() external;

    /// @notice Callback hook that is called by Governance after the LQTY allocation is updated by a user
    /// @param _user Address of the user that updated their LQTY allocation
    /// @param _voteLQTY Allocated voting LQTY
    /// @param _vetoLQTY Allocated vetoing LQTY
    function onAfterAllocateLQTY(address _user, uint96 _voteLQTY, uint96 _vetoLQTY) external;

    /// @notice Callback hook that is called by Governance after the claim for the last epoch was distributed
    /// to the initiative
    /// @param _bold Amount of BOLD that was distributed
    function onClaimForInitiative(uint256 _bold) external;
}
