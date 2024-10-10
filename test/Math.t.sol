// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {add, abs} from "src/utils/Math.sol";


contract AddComparer {
    function libraryAdd(uint88 a, int96 b) public pure returns (uint88) {
        return add(a, b);
    }
    // Differential test
    // Verify that it will revert any time it overflows
    // Verify we can never get a weird value
    function referenceAdd(int96 a, int96 b) public pure returns (int96) {
        return a + b;
    }
}
contract AbsComparer {
    function libraryAbs(int96 a) public pure returns (int96) {
        return int96(abs(a)); // by definition should fit, since input was int96 -> uint96 -> int96
    }

    function referenceAbs(int96 a) public pure returns (int96) {
        return a < 0 ? -a : a;
    }
}
contract MathTests is Test {


    // forge test --match-test test_math_fuzz_comparison -vv
    function test_math_fuzz_comparison(uint88 a, int96 b) public {
        AddComparer tester = new AddComparer();

        bool revertLib;
        bool revertRef;
        int96 resultLib;
        int96 resultRef;

        try tester.libraryAdd(a, b) returns (uint88 x) {
            resultLib = int96(uint96(x));
        } catch {
            revertLib = true;
        }

        try tester.referenceAdd(int96(uint96(a)), b) returns (int96 x) {
            resultRef = int96(uint96(x));
        } catch {
            revertRef = true;
        }

        // Negative overflow
        if(revertLib == true && revertRef == false) {
            // Check if we had a negative value
            if(resultRef < 0) {
                revertRef = true;
                resultRef = int96(0);
            }

            // Check if we overflow on the positive
            if(resultRef > int96(uint96(type(uint88).max))) {
                // Overflow due to above limit
                revertRef = true;
                resultRef = int96(0);
            }
        }

        assertEq(revertLib, revertRef, "Reverts"); // This breaks 
        assertEq(resultLib, resultRef, "Results"); // This should match excluding overflows
    }



    /// @dev test that abs never incorrectly overflows
    // forge test --match-test test_fuzz_abs_comparison -vv
    function test_fuzz_abs_comparison(int96 a) public {
        AbsComparer tester = new AbsComparer();

        bool revertLib;
        bool revertRef;
        int96 resultLib;
        int96 resultRef;

        try tester.libraryAbs(a) returns (int96 x) {
            resultLib = x;
        } catch {
            revertLib = true;
        }

        try tester.referenceAbs(a) returns (int96 x) {
            resultRef = x;
        } catch {
            revertRef = true;
        }

        assertEq(revertLib, revertRef, "reverts");
        assertEq(resultLib, resultRef, "results");
    }

    /// @dev Test that Abs never revert
    ///     It reverts on the smaller possible number
    function test_fuzz_abs(int96 a) public {
        /**
            Encountered 1 failing test in test/Math.t.sol:MathTests
            [FAIL. Reason: panic: arithmetic underflow or overflow (0x11); counterexample: calldata=0x804d552cffffffffffffffffffffffffffffffffffffffff800000000000000000000000 args=[-39614081257132168796771975168 [-3.961e28]]] test_fuzz_abs(int96) (runs: 0, μ: 0, ~: 0)
        */
        vm.assume(a > type(int96).min);
        /// @audit Reverts at the absolute minimum due to overflow as it will remain negative
        abs(a);
    }
}