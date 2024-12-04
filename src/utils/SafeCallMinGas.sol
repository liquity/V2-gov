// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Given the gas requirement, ensures that the current context has sufficient gas to perform a call + a fixed buffer
/// @dev Credits: https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/libraries/SafeCall.sol#L100-L107
function hasMinGas(uint256 _minGas, uint256 _reservedGas) view returns (bool) {
    bool _hasMinGas;
    assembly {
        // Equation: gas × 63 ≥ minGas × 64 + 63(40_000 + reservedGas)
        _hasMinGas := iszero(lt(mul(gas(), 63), add(mul(_minGas, 64), mul(add(40000, _reservedGas), 63))))
    }
    return _hasMinGas;
}

/// @dev Performs a call ignoring the recipient existing or not, passing the exact gas value, ignoring any return value
function safeCallWithMinGas(address _target, uint256 _gas, uint256 _value, bytes memory _calldata)
    returns (bool success)
{
    /// This is not necessary
    /// But this is basically a worst case estimate of mem exp cost + operations before the call
    require(hasMinGas(_gas, 1_000), "Must have minGas");

    // dispatch message to recipient
    // by assembly calling "handle" function
    // we call via assembly to avoid memcopying a very large returndata
    // returned by a malicious contract
    assembly {
        success :=
            call(
                _gas, // gas
                _target, // recipient
                _value, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )

        // Ignore all return values
    }
    return (success);
}
