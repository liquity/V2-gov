// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMultiDelegateCall {
    /// @notice Call multiple functions of the contract while preserving `msg.sender`
    /// @param inputs Function calls to perform, encoded using `abi.encodeCall()` or equivalent
    /// @return returnValues Raw data returned by each call
    function multiDelegateCall(bytes[] calldata inputs) external returns (bytes[] memory returnValues);
}
