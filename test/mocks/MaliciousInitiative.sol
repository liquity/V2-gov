// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IInitiative} from "src/interfaces/IInitiative.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";

contract MaliciousInitiative is IInitiative {
    enum FunctionType {
        NONE,
        REGISTER,
        UNREGISTER,
        ALLOCATE,
        CLAIM
    }

    enum RevertType {
        NONE,
        THROW,
        OOG,
        RETURN_BOMB,
        REVERT_BOMB
    }

    mapping(FunctionType => RevertType) revertBehaviours;

    /// @dev specify the revert behaviour on each function
    function setRevertBehaviour(FunctionType ft, RevertType rt) external {
        revertBehaviours[ft] = rt;
    }

    // Do stuff on each hook
    function onRegisterInitiative(uint256) external view override {
        _performRevertBehaviour(revertBehaviours[FunctionType.REGISTER]);
    }

    function onUnregisterInitiative(uint256) external view override {
        _performRevertBehaviour(revertBehaviours[FunctionType.UNREGISTER]);
    }

    function onAfterAllocateLQTY(
        uint256,
        address,
        IGovernance.UserState calldata,
        IGovernance.Allocation calldata,
        IGovernance.InitiativeState calldata
    ) external view override {
        _performRevertBehaviour(revertBehaviours[FunctionType.ALLOCATE]);
    }

    function onClaimForInitiative(uint256, uint256) external view override {
        _performRevertBehaviour(revertBehaviours[FunctionType.CLAIM]);
    }

    function _performRevertBehaviour(RevertType action) internal pure {
        if (action == RevertType.THROW) {
            revert("A normal Revert");
        }

        // 3 gas per iteration, consider changing to storage changes if traces are cluttered
        if (action == RevertType.OOG) {
            uint256 i;
            while (true) {
                ++i;
            }
        }

        if (action == RevertType.RETURN_BOMB) {
            uint256 _bytes = 2_000_000;
            assembly {
                return(0, _bytes)
            }
        }

        if (action == RevertType.REVERT_BOMB) {
            uint256 _bytes = 2_000_000;
            assembly {
                revert(0, _bytes)
            }
        }

        return; // NONE
    }
}
