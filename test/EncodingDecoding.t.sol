// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {EncodingDecodingLib} from "src/utils/EncodingDecodingLib.sol";

contract EncodingDecodingTest is Test {
    // value -> encoding -> decoding -> value
    function test_encoding_and_decoding_symmetrical(uint88 lqty, uint32 averageTimestamp) public {
        uint224 encodedValue = EncodingDecodingLib.encodeLQTYAllocation(lqty, averageTimestamp);
        (uint88 decodedLqty, uint32 decodedAverageTimestamp) = EncodingDecodingLib.decodeLQTYAllocation(encodedValue);

        assertEq(lqty, decodedLqty);
        assertEq(averageTimestamp, decodedAverageTimestamp);

        // Redo
        uint224 reEncoded = EncodingDecodingLib.encodeLQTYAllocation(decodedLqty, decodedAverageTimestamp);
        (uint88 reDecodedLqty, uint32 reDecodedAverageTimestamp) =
            EncodingDecodingLib.decodeLQTYAllocation(encodedValue);

        assertEq(reEncoded, encodedValue);
        assertEq(reDecodedLqty, decodedLqty);
        assertEq(reDecodedAverageTimestamp, decodedAverageTimestamp);
    }

    /// We expect this test to fail as the encoding is ambigous past u120
    function testFail_encoding_not_equal_reproducer() public {
        _receive_undo_compare(18371677541005923091065047412368542483005086202);
    }

    // receive -> undo -> check -> redo -> compare
    function test_receive_undo_compare(uint120 encodedValue) public {
        _receive_undo_compare(encodedValue);
    }

    // receive -> undo -> check -> redo -> compare
    function _receive_undo_compare(uint224 encodedValue) public {
        /// These values fail because we could pass a value that is bigger than intended
        (uint88 decodedLqty, uint32 decodedAverageTimestamp) = EncodingDecodingLib.decodeLQTYAllocation(encodedValue);

        uint224 encodedValue2 = EncodingDecodingLib.encodeLQTYAllocation(decodedLqty, decodedAverageTimestamp);
        (uint88 decodedLqty2, uint32 decodedAverageTimestamp2) = EncodingDecodingLib.decodeLQTYAllocation(encodedValue2);

        assertEq(encodedValue, encodedValue2, "encoded values not equal");
        assertEq(decodedLqty, decodedLqty2, "decoded lqty not equal");
        assertEq(decodedAverageTimestamp, decodedAverageTimestamp2, "decoded timestamps not equal");
    }
}
