// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {add, abs} from "src/utils/Math.sol";
import {console} from "forge-std/console.sol";

contract AddComparer {
    function libraryAdd(uint88 a, int88 b) public pure returns (uint88) {
        return add(a, b);
    }
    // Differential test
    // Verify that it will revert any time it overflows
    // Verify we can never get a weird value

    function referenceAdd(uint88 a, int88 b) public pure returns (uint88) {
        // Upscale both
        int96 scaledA = int96(int256(uint256(a)));
        int96 tempB = int96(b);

        int96 res = scaledA + tempB;
        if (res < 0) {
            revert("underflow");
        }

        if (res > int96(int256(uint256(type(uint88).max)))) {
            revert("Too big");
        }

        return uint88(uint96(res));
    }
}

contract AbsComparer {
    function libraryAbs(int88 a) public pure returns (uint88) {
        return abs(a); // by definition should fit, since input was int88 -> uint88 -> int88
    }

    event DebugEvent2(int256);
    event DebugEvent(uint256);

    function referenceAbs(int88 a) public returns (uint88) {
        int256 bigger = a;
        uint256 ref = bigger < 0 ? uint256(-bigger) : uint256(bigger);
        emit DebugEvent2(bigger);
        emit DebugEvent(ref);
        if (ref > type(uint88).max) {
            revert("Too big");
        }
        if (ref < type(uint88).min) {
            revert("Too small");
        }
        return uint88(ref);
    }
}

contract MathTests is Test {
    // forge test --match-test test_math_fuzz_comparison -vv
    function test_math_fuzz_comparison(uint88 a, int88 b) public {
        vm.assume(a < uint88(type(int88).max));
        AddComparer tester = new AddComparer();

        bool revertLib;
        bool revertRef;
        uint88 resultLib;
        uint88 resultRef;

        try tester.libraryAdd(a, b) returns (uint88 x) {
            resultLib = x;
        } catch {
            revertLib = true;
        }

        try tester.referenceAdd(a, b) returns (uint88 x) {
            resultRef = x;
        } catch {
            revertRef = true;
        }

        // Negative overflow
        if (revertLib == true && revertRef == false) {
            // Check if we had a negative value
            if (resultRef < 0) {
                revertRef = true;
                resultRef = uint88(0);
            }

            // Check if we overflow on the positive
            if (resultRef > uint88(type(int88).max)) {
                // Overflow due to above limit
                revertRef = true;
                resultRef = uint88(0);
            }
        }

        assertEq(revertLib, revertRef, "Reverts"); // This breaks
        assertEq(resultLib, resultRef, "Results"); // This should match excluding overflows
    }

    /// @dev test that abs never incorrectly overflows
    // forge test --match-test test_fuzz_abs_comparison -vv
    /**
     * [FAIL. Reason: reverts: false != true; counterexample: calldata=0x2c945365ffffffffffffffffffffffffffffffffffffffffff8000000000000000000000 args=[-154742504910672534362390528 [-1.547e26]]]
     */
    function test_fuzz_abs_comparison(int88 a) public {
        AbsComparer tester = new AbsComparer();

        bool revertLib;
        bool revertRef;
        uint88 resultLib;
        uint88 resultRef;

        try tester.libraryAbs(a) returns (uint88 x) {
            resultLib = x;
        } catch {
            revertLib = true;
        }

        try tester.referenceAbs(a) returns (uint88 x) {
            resultRef = x;
        } catch {
            revertRef = true;
        }

        assertEq(revertLib, revertRef, "reverts");
        assertEq(resultLib, resultRef, "results");
    }

    /// @dev Test that Abs never revert
    ///     It reverts on the smaller possible number
    function test_fuzz_abs(int88 a) public {
        /**
         * Encountered 1 failing test in test/Math.t.sol:MathTests
         *         [FAIL. Reason: panic: arithmetic underflow or overflow (0x11); counterexample: calldata=0x804d552cffffffffffffffffffffffffffffffffffffffff800000000000000000000000 args=[-39614081257132168796771975168 [-3.961e28]]] test_fuzz_abs(int88) (runs: 0, μ: 0, ~: 0)
         */
        /// @audit Reverts at the absolute minimum due to overflow as it will remain negative
        abs(a);
    }
}
