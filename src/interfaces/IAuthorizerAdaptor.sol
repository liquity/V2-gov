// SPDX-License-Identifier: GPL-3.0-or-later

interface IAuthorizerAdaptor {
    /**
     * @notice Performs an arbitrary function call on a target contract, provided the caller is authorized to do so.
     * @param target - Address of the contract to be called
     * @param data - Calldata to be sent to the target contract
     * @return The bytes encoded return value from the performed function call
     */
    function performAction(address target, bytes calldata data) external payable returns (bytes memory);
}
