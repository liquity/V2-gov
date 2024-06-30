// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

contract UniV4Donations {
    IGovernance public immutable governance;
    IERC20 public immutable bold;

    uint256 public immutable VESTING_EPOCH_START;
    uint256 public immutable VESTING_EPOCH_DURATION;

    struct Vesting {
        uint240 amount;
        uint16 epoch;
    }

    Vesting public vesting;

    constructor(address _governance, address _bold) {
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        VESTING_EPOCH_START = IGovernance(_governance).EPOCH_START();
        VESTING_EPOCH_DURATION = IGovernance(_governance).EPOCH_DURATION();
    }

    function vestingEpoch() public view returns (uint16) {
        return uint16(((block.timestamp - VESTING_EPOCH_START) / VESTING_EPOCH_DURATION));
    }

    function vestingEpochStart() public view returns (uint256) {
        return VESTING_EPOCH_START + (vestingEpoch() * VESTING_EPOCH_DURATION);
    }

    function restartVesting() public returns (Vesting memory) {
        uint16 epoch = vestingEpoch();
        Vesting memory _vesting = vesting;
        if (_vesting.epoch < epoch) {
            _vesting.amount = uint240(bold.balanceOf(address(this)));
            _vesting.epoch = epoch;
            vesting = _vesting;
        }
        return _vesting;
    }

    function donateToPool() public returns (uint256) {
        Vesting memory _vesting = restartVesting();
        uint256 amount = _vesting.amount * (block.timestamp - vestingEpochStart()) / VESTING_EPOCH_DURATION;
        // dondate to pool
        return amount;
    }

    function claimAndDonateToPool() external returns (uint256) {
        governance.claimForInitiative(address(this));
        return donateToPool();
    }
}
