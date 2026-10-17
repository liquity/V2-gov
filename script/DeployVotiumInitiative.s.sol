// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";

import "src/VotiumInitiative.sol";

contract DeployVotiumInitiative is Script {
    address constant GOVERNANCE_ADDRESS = 0x807DEf5E7d057DF05C796F4bc75C3Fe82Bd6EeE1;
    address constant BOLD_TOKEN_ADDRESS = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address constant CRV_TOKEN_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant VOTIUM_ADDRESS = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    address constant GAUGE_ADDRESS = 0x07a01471fA544D9C6531B631E6A96A79a9AD05E9;
    uint32 constant EPOCH_DURATION = 604800;

    address deployer;

    function run() external {
        if (vm.envBytes("DEPLOYER").length == 20) {
            // address
            deployer = vm.envAddress("DEPLOYER");
            vm.startBroadcast(deployer);
        } else {
            // private key
            uint256 privateKey = vm.envUint("DEPLOYER");
            deployer = vm.addr(privateKey);
            vm.startBroadcast(privateKey);
        }

        console2.log("deployer: ", deployer);
        console2.log("Chain Id: ", block.chainid);

        VotiumInitiative votiumInitiative = new VotiumInitiative(
            GOVERNANCE_ADDRESS, BOLD_TOKEN_ADDRESS, CRV_TOKEN_ADDRESS, VOTIUM_ADDRESS, GAUGE_ADDRESS, EPOCH_DURATION
        );

        console2.log("Deployed VotiumInitiative: ", address(votiumInitiative));
    }
}
