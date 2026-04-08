// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "./ILiquidityGauge.sol";

/// @notice Taken from Balancer V2
interface ILiquidityGaugeFactory {
    /**
     * @notice Returns true if `gauge` was created by this factory.
     */
    function isGaugeFromFactory(address gauge) external view returns (bool);

    function create(address pool, uint256 relativeWeightCap) external returns (address);
}
