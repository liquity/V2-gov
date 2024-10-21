// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library EncodingDecodingLib {
    function encodeLQTYAllocation(uint88 _lqty, uint32 _averageTimestamp) internal pure returns (uint224) {
        uint224 _value = (uint224(_lqty) << 32) | _averageTimestamp;
        return _value;
    }

    function decodeLQTYAllocation(uint224 _value) internal pure returns (uint88, uint32) {
        return (uint88(_value >> 32), uint32(_value));
    }
}
