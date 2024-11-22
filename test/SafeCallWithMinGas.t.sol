// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {safeCallWithMinGas} from "src/utils/SafeCallMinGas.sol";

contract BasicRecipient {
    bool public callWasValid;

    function validCall() external {
        callWasValid = true;
    }
}

contract FallbackRecipient {
    bytes public received;

    fallback() external payable {
        received = msg.data;
    }
}

contract SafeCallWithMinGasTests is Test {
    function test_basic_nonExistent(uint256 gas, uint256 value, bytes memory theData) public {
        gas = bound(gas, 0, 30_000_000);

        // Call to non existent succeeds
        address nonExistent = address(0x123123123);
        assert(nonExistent.code.length == 0);

        safeCallWithMinGas(address(0x123123123), gas, value, theData);
    }

    function test_basic_contractData(uint256 gas, uint256 value, bytes memory theData) public {
        gas = bound(gas, 50_000 + theData.length * 2_100, 30_000_000);

        /// @audit Approximation
        FallbackRecipient recipient = new FallbackRecipient();
        // Call to non existent succeeds

        vm.deal(address(this), value);

        safeCallWithMinGas(address(recipient), gas, value, theData);
        assertEq(keccak256(recipient.received()), keccak256(theData), "same data");
    }

    function test_basic_contractCall() public {
        BasicRecipient recipient = new BasicRecipient();
        // Call to non existent succeeds

        safeCallWithMinGas(address(recipient), 35_000, 0, abi.encodeCall(BasicRecipient.validCall, ()));
        assertEq(recipient.callWasValid(), true, "Call success");
    }
}
