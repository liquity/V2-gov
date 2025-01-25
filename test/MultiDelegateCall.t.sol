// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {MultiDelegateCall} from "../src/utils/MultiDelegateCall.sol";

contract Target is MultiDelegateCall {
    error CustomError(string);

    function id(bytes calldata x) external pure returns (bytes calldata) {
        return x;
    }

    function revertWithMessage(string calldata message) external pure {
        revert(message);
    }

    function revertWithCustomError(string calldata message) external pure {
        revert CustomError(message);
    }

    function panicWithArithmeticError() external pure returns (int256) {
        return -type(int256).min;
    }
}

contract MultiDelegateCallTest is Test {
    function test_CallsAllInputsAndAggregatesResults() external {
        Target target = new Target();

        bytes[] memory inputValues = new bytes[](3);
        inputValues[0] = abi.encode("asd", 123);
        inputValues[1] = abi.encode("fgh", 456);
        inputValues[2] = abi.encode("jkl", 789);

        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encodeCall(target.id, (inputValues[0]));
        inputs[1] = abi.encodeCall(target.id, (inputValues[1]));
        inputs[2] = abi.encodeCall(target.id, (inputValues[2]));

        bytes[] memory returnValues = target.multiDelegateCall(inputs);
        assertEq(returnValues.length, inputs.length, "returnValues.length != inputs.length");

        assertEq(abi.decode(returnValues[0], (bytes)), inputValues[0], "returnValues[0]");
        assertEq(abi.decode(returnValues[1], (bytes)), inputValues[1], "returnValues[1]");
        assertEq(abi.decode(returnValues[2], (bytes)), inputValues[2], "returnValues[2]");
    }

    function test_StopsAtFirstRevertAndBubblesItUp() external {
        Target target = new Target();

        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encodeCall(target.id, ("asd"));
        inputs[1] = abi.encodeCall(target.revertWithMessage, ("fgh"));
        inputs[2] = abi.encodeCall(target.revertWithMessage, ("jkl"));

        vm.expectRevert(bytes("fgh"));
        target.multiDelegateCall(inputs);
    }

    function test_CanBubbleCustomError() external {
        Target target = new Target();

        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encodeCall(target.id, ("asd"));
        inputs[1] = abi.encodeCall(target.revertWithCustomError, ("fgh"));
        inputs[2] = abi.encodeCall(target.revertWithMessage, ("jkl"));

        vm.expectRevert(abi.encodeWithSelector(Target.CustomError.selector, "fgh"));
        target.multiDelegateCall(inputs);
    }

    function test_CanBubblePanic() external {
        Target target = new Target();

        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encodeCall(target.id, ("asd"));
        inputs[1] = abi.encodeCall(target.panicWithArithmeticError, ());
        inputs[2] = abi.encodeCall(target.revertWithMessage, ("jkl"));

        vm.expectRevert(stdError.arithmeticError);
        target.multiDelegateCall(inputs);
    }
}
