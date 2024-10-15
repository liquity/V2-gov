// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BeforeAfter} from "../BeforeAfter.sol";

abstract contract GovernanceProperties is BeforeAfter {
    
    function property_GV01() public {
        // first check that epoch hasn't changed after the operation
        if(_before.epoch == _after.epoch) {
            // loop through the initiatives and check that their status hasn't changed
            for(uint8 i; i < deployedInitiatives.length; i++) {
                address initiative = deployedInitiatives[i];
                eq(uint256(_before.initiativeStatus[initiative]), uint256(_after.initiativeStatus[initiative]), "GV-01: Initiative state should only return one state per epoch");
            }
        }
    }

}