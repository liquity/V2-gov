// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

contract CurveV2GaugeRewardsNoBribesInitiative is IInitiative {
    IGovernance public immutable governance;
    IERC20 public immutable bold;

    ILiquidityGauge public immutable gauge;
    uint256 public immutable duration;

    event DepositIntoGauge(uint256 amount);

    constructor(address _governance, address _bold, address _gauge, uint256 _duration) {
        require(_governance != address(0), "Governance must be set");
        require(_bold != address(0), "Bold token must be set");
        require(_gauge != address(0), "Gauge must be set");
        require(_duration > 0, "Duration must be set");

        governance = IGovernance(_governance);
        bold = IERC20(_bold);

        gauge = ILiquidityGauge(_gauge);
        duration = _duration;
    }

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "Unauthorized");
        _;
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative(uint256) external override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint256) external override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onAfterAllocateLQTY(
        uint256,
        address,
        IGovernance.UserState calldata,
        IGovernance.Allocation calldata,
        IGovernance.InitiativeState calldata
    ) external override onlyGovernance {}

    /// @notice Governance transfers Bold, and we deposit it into the gauge
    /// @dev Doing this allows anyone to trigger the claim
    function onClaimForInitiative(uint256, uint256) external override onlyGovernance {}

    // Wrapper to avoid gas limitation
    function claimForInitiative() external {
        uint256 claimableAmount = governance.claimForInitiative(address(this));
        uint256 amount = bold.balanceOf(address(this));
        assert(amount >= claimableAmount);
        require(amount > 0, "CurveV2GaugeRewardsNoBribesInitiative: no funds for campaign");

        // For small donations queue them into the contract
        if (amount < duration * 1000) {
            return;
        }

        bold.approve(address(gauge), amount);
        gauge.deposit_reward_token(address(bold), amount, duration);

        emit DepositIntoGauge(amount);
    }
}
