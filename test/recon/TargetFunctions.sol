
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {safeCallWithMinGas} from "./utils/SafeCallMinGas.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {

    function initiative_onRegisterInitiative(uint16 epoch) public {
        bool callWithMinGas = safeCallWithMinGas(address(initiative), MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onRegisterInitiative, (epoch)));
        
        t(callWithMinGas, "call to onRegisterInitiative reverts with minimum gas");
    }
    
    function intiative_onUnregisterInitiative(uint16 epoch) public {
        bool callWithMinGas = safeCallWithMinGas(address(initiative), MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onUnregisterInitiative, (epoch)));
        
        t(callWithMinGas, "call to onUnregisterInitiative reverts with minimum gas");
    }
    
    function initiative_onAfterAllocateLQTY(uint16 currentEpoch, address user, uint88 voteLQTY, uint88 vetoLQTY) public {
        bool callWithMinGas = safeCallWithMinGas(address(initiative), MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onAfterAllocateLQTY, (currentEpoch, user, voteLQTY, vetoLQTY)));

        t(callWithMinGas, "call to onAfterAllocateLQTY reverts with minimum gas");
    }

    function initiative_onClaimForInitiative(uint16 claimEpoch, uint256 bold) public {
        bool callWithMinGas = safeCallWithMinGas(address(initiative), MIN_GAS_TO_HOOK, 0, abi.encodeCall(IInitiative.onClaimForInitiative, (claimEpoch, bold)));
        
        t(callWithMinGas, "call to onClaimForInitiative reverts with minimum gas");
    }



}
