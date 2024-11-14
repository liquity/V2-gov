// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernance} from "./IGovernance.sol";

interface IInitiative {
    /// @notice Callback hook that is called by Governance after the initiative was successfully registered
    /// @param _atEpoch Epoch at which the initiative is registered
    function onRegisterInitiative(uint16 _atEpoch) external;

    /// @notice Callback hook that is called by Governance after the initiative was unregistered
    /// @param _atEpoch Epoch at which the initiative is unregistered
    function onUnregisterInitiative(uint16 _atEpoch) external;

    /// @notice Callback hook that is called by Governance after the LQTY allocation is updated by a user
    /// @param _currentEpoch Epoch at which the LQTY allocation is updated
    /// @param _user Address of the user that updated their LQTY allocation
    /// @param _allocatedLQTY Total LQTY allocated by user for the initiative
    /// @param _voteOffset TODO..., it corresponds to y-intercept
    /// @param _isVeto It’s vetoing the intiative if true,  vouching for it otherwise
    /// @param _userState User state
    /// @param _initiativeState Initiative state
    function onAfterAllocateLQTY(
        uint16 _currentEpoch,
        address _user,
        uint88 _allocatedLQTY,
        uint160 _voteOffset,
        bool _isVeto,
        IGovernance.UserState calldata _userState,
        IGovernance.InitiativeState calldata _initiativeState
    ) external;

    /// @notice Callback hook that is called by Governance after the claim for the last epoch was distributed
    /// to the initiative
    /// @param _claimEpoch Epoch at which the claim was distributed
    /// @param _bold Amount of BOLD that was distributed
    function onClaimForInitiative(uint16 _claimEpoch, uint256 _bold) external;
}
