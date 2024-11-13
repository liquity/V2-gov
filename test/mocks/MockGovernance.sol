// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockGovernance {
    uint16 private __epoch;

    uint32 public constant EPOCH_START = 0;
    uint32 public constant EPOCH_DURATION = 7 days;

    function claimForInitiative(address) external pure returns (uint256) {
        return 1000e18;
    }

    function setEpoch(uint16 _epoch) external {
        __epoch = _epoch;
    }

    function epoch() external view returns (uint16) {
        return __epoch;
    }

    function _averageAge(uint120 _currentTimestamp, uint120 _averageTimestamp) internal pure returns (uint120) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function lqtyToVotes(uint88 _lqtyAmount, uint120 _currentTimestamp, uint120 _averageTimestamp)
        public
        pure
        returns (uint208)
    {
        return uint208(_lqtyAmount) * uint208(_averageAge(_currentTimestamp, _averageTimestamp));
    }
}
