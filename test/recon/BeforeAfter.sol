
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract BeforeAfter is Setup, Asserts {

    struct Vars {
        mapping(address => mapping(uint16 => bool)) claimedBribeAtEpoch;
        uint128 lqtyBalance;
        uint128 lusdBalance;
    }

    Vars internal _before;
    Vars internal _after;

    modifier withChecks {
        __before();
        _;
        __after();
    }

    function __before() internal {
        // only have one user so can set this individually
        // NOTE: if more users (actors) are added this will need to loop over all users
        _before.claimedBribeAtEpoch[user][governance.epoch()];
        _before.lqtyBalance = uint128(lqty.balanceOf(user));
        _before.lusdBalance = uint128(lusd.balanceOf(user));
    }

    function __after() internal {
        _after.claimedBribeAtEpoch[user][governance.epoch()];
        _after.lqtyBalance = uint128(lqty.balanceOf(user));
        _after.lusdBalance = uint128(lusd.balanceOf(user));
    }
}
