// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";

import "src/CurveV2GaugeRewardsNoBribesInitiative.sol";

contract DeployCurveV2GaugeRewardsNoBribesInitiative is Script {
    address constant GOVERNANCE_ADDRESS = 0x807DEf5E7d057DF05C796F4bc75C3Fe82Bd6EeE1;
    address constant BOLD_TOKEN_ADDRESS = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
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

        CurveV2GaugeRewardsNoBribesInitiative curveV2GaugeRewardsNoBribesInitiative = new CurveV2GaugeRewardsNoBribesInitiative(
            GOVERNANCE_ADDRESS, BOLD_TOKEN_ADDRESS, GAUGE_ADDRESS, EPOCH_DURATION
        );

        console2.log("Deployed CurveV2GaugeRewardsNoBribesInitiative: ", address(curveV2GaugeRewardsNoBribesInitiative));
    }
}
