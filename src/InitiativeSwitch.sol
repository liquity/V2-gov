// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {IBribeInitiative} from "./interfaces/IBribeInitiative.sol";

contract InitiativeSwitch is IInitiative, /* , IBribeInitiative */ Ownable {
    using SafeERC20 for IERC20;

    IGovernance public immutable governance;
    IERC20 public immutable bold;
    IInitiative public target;

    event TargetSwitch(address _newTarget);

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "InitiativeSwitch: invalid-sender");
        _;
    }

    constructor(IGovernance _governance, IInitiative _target) Ownable(msg.sender) {
        governance = _governance;
        bold = _governance.bold();
        target = _target;
    }

    function switchTarget(IInitiative _target) external onlyOwner {
        uint256 epoch = governance.epoch();
        target.onUnregisterInitiative(epoch);
        _target.onRegisterInitiative(epoch);

        target = _target;

        emit TargetSwitch(address(_target));
    }

    // TODO: escape hatch

    // IInitiative interface

    function onRegisterInitiative(uint256 _atEpoch) external override onlyGovernance {
        target.onRegisterInitiative(_atEpoch);
    }

    function onUnregisterInitiative(uint256 _atEpoch) external override onlyGovernance {
        target.onUnregisterInitiative(_atEpoch);
    }

    function onAfterAllocateLQTY(
        uint256 _currentEpoch,
        address _user,
        IGovernance.UserState calldata _userState,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external override onlyGovernance {
        target.onAfterAllocateLQTY(_currentEpoch, _user, _userState, _allocation, _initiativeState);
    }

    function onClaimForInitiative(uint256 _claimEpoch, uint256 _bold) external override onlyGovernance {
        bold.safeTransfer(address(target), bold.balanceOf(address(this)));
        target.onClaimForInitiative(_claimEpoch, _bold);
    }

    // TODO: IBribeInitiative interface
}
