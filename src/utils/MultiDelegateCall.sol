// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMultiDelegateCall} from "../interfaces/IMultiDelegateCall.sol";

contract MultiDelegateCall is IMultiDelegateCall {
    /// @inheritdoc IMultiDelegateCall
    function multiDelegateCall(bytes[] calldata inputs) external returns (bytes[] memory returnValues) {
        returnValues = new bytes[](inputs.length);

        for (uint256 i; i < inputs.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(inputs[i]);

            if (!success) {
                // Bubble up the revert
                assembly {
                    revert(
                        add(32, returnData), // offset (skip first 32 bytes, where the size of the array is stored)
                        mload(returnData) // size
                    )
                }
            }

            returnValues[i] = returnData;
        }
    }
}
