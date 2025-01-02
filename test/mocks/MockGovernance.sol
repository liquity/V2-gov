// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockGovernance {
    uint256 private __epoch;

    uint256 public constant EPOCH_START = 0;
    uint256 public constant EPOCH_DURATION = 7 days;

    function claimForInitiative(address) external pure returns (uint256) {
        return 1000e18;
    }

    function setEpoch(uint256 _epoch) external {
        __epoch = _epoch;
    }

    function epoch() external view returns (uint256) {
        return __epoch;
    }

    function _averageAge(uint256 _currentTimestamp, uint256 _averageTimestamp) internal pure returns (uint256) {
        if (_averageTimestamp == 0 || _currentTimestamp < _averageTimestamp) return 0;
        return _currentTimestamp - _averageTimestamp;
    }

    function lqtyToVotes(uint256 _lqtyAmount, uint256 _currentTimestamp, uint256 _averageTimestamp)
        public
        pure
        returns (uint256)
    {
        return uint256(_lqtyAmount) * uint256(_averageAge(_currentTimestamp, _averageTimestamp));
    }
}
