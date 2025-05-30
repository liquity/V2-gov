// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IInitiative} from "../../src/interfaces/IInitiative.sol";

contract MockReentrantInitiative is IInitiative {
    IGovernance public immutable governance;

    constructor(address _governance) {
        governance = IGovernance(_governance);
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative(uint256) external virtual override {
        governance.registerInitiative(address(0));
    }

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint256) external virtual override {
        governance.unregisterInitiative(address(0));
    }

    /// @inheritdoc IInitiative
    function onAfterAllocateLQTY(
        uint256,
        address,
        IGovernance.UserState calldata,
        IGovernance.Allocation calldata,
        IGovernance.InitiativeState calldata
    ) external virtual {
        address[] memory initiatives = new address[](0);
        int256[] memory deltaLQTYVotes = new int256[](0);
        int256[] memory deltaLQTYVetos = new int256[](0);
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint256, uint256) external virtual override {
        governance.claimForInitiative(address(0));
    }
}

contract MockInitiative is IInitiative {
    struct OnAfterAllocateLQTYParams {
        uint256 currentEpoch;
        address user;
        IGovernance.UserState userState;
        IGovernance.Allocation allocation;
        IGovernance.InitiativeState initiativeStat;
    }

    OnAfterAllocateLQTYParams[] public onAfterAllocateLQTYCalls;

    function numOnAfterAllocateLQTYCalls() external view returns (uint256) {
        return onAfterAllocateLQTYCalls.length;
    }

    function onAfterAllocateLQTY(
        uint256 _currentEpoch,
        address _user,
        IGovernance.UserState calldata _userState,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external override {
        onAfterAllocateLQTYCalls.push(
            OnAfterAllocateLQTYParams(_currentEpoch, _user, _userState, _allocation, _initiativeState)
        );
    }

    function onRegisterInitiative(uint256) external override {}
    function onUnregisterInitiative(uint256) external override {}
    function onClaimForInitiative(uint256, uint256) external override {}
}
