// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockGovernance {
    uint16 private __epoch;

    function claimForInitiative(address) external pure returns (uint256) {
        return 1000e18;
    }

    function setEpoch(uint16 _epoch) external {
        __epoch = _epoch;
    }

    function epoch() external view returns (uint16) {
        return __epoch;
    }

    function _averageAge(uint32 _currentTimestamp, uint32 _averageTimestamp) internal pure returns (uint32) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function lqtyToVotes(uint88 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp)
        public
        pure
        returns (uint240)
    {
        return uint240(_lqtyAmount) * _averageAge(uint32(_currentTimestamp), _averageTimestamp);
    }
}
