// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IInitiative} from "../../src/interfaces/IInitiative.sol";

contract MockInitiative is IInitiative {
    IGovernance public immutable governance;

    constructor(address _governance) {
        governance = IGovernance(_governance);
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative(uint16) external virtual override {
        governance.registerInitiative(address(0));
    }

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint16) external virtual override {
        governance.unregisterInitiative(address(0));
    }

    /// @inheritdoc IInitiative
    function onAfterAllocateLQTY(
        uint16,
        address,
        IGovernance.UserState calldata,
        IGovernance.UserInitiativeAllocation calldata,
        IGovernance.InitiativeState calldata
    ) external virtual {
        address[] memory initiatives = new address[](0);
        int88[] memory deltaLQTYVotes = new int88[](0);
        int88[] memory deltaLQTYVetos = new int88[](0);
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint16, uint256) external virtual override {
        governance.claimForInitiative(address(0));
    }
}
