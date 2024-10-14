
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {

    function property_BI02() public {
        t(!claimedTwice, "B2-01: User can only claim bribes once in an epoch");
    }
}
