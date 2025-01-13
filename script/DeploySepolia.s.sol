// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {CurveV2GaugeRewards} from "../src/CurveV2GaugeRewards.sol";

import {MockERC20Tester} from "../test/mocks/MockERC20Tester.sol";
import {MockStakingV1} from "../test/mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "../test/mocks/MockStakingV1Deployer.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract DeploySepoliaScript is Script, MockStakingV1Deployer {
    // Environment Constants
    MockERC20Tester private lqty;
    MockERC20Tester private bold;
    MockStakingV1 private stakingV1;
    MockERC20Tester private usdc;

    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(address(0xfb37b8D939FFa77114005e61CFc2e543d6F49A81));

    // Governance Constants
    uint128 private constant REGISTRATION_FEE = 100e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.001e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 3e18;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.03e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    // CurveV2GaugeRewards Constants
    uint256 private constant DURATION = 7 days;

    // Contracts
    Governance private governance;
    address[] private initialInitiatives;
    CurveV2GaugeRewards private curveV2GaugeRewards;
    ICurveStableswapNG private curvePool;
    ILiquidityGauge private gauge;

    // Deployer
    address private deployer;
    uint256 private privateKey;
    uint256 private nonce;

    function setUp() public {
        privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.createWallet(privateKey).addr;
        nonce = vm.getNonce(deployer);
    }

    function deployEnvironment() private {
        (stakingV1, lqty,) = deployMockStakingV1();
        bold = new MockERC20Tester("Bold", "BOLD");
        usdc = new MockERC20Tester("USD Coin", "USDC");
    }

    function deployGovernance() private {
        governance = new Governance(
            address(lqty),
            address(bold),
            address(stakingV1),
            address(bold),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp - EPOCH_DURATION,
                /// @audit Ensures that `initialInitiatives` can be voted on
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            deployer,
            initialInitiatives
        );
    }

    function deployCurveV2GaugeRewards(uint256 _nonce) private {
        address[] memory _coins = new address[](2);
        _coins[0] = address(bold);
        _coins[1] = address(usdc);
        uint8[] memory _asset_types = new uint8[](2);
        _asset_types[0] = 0;
        _asset_types[1] = 0;
        bytes4[] memory _method_ids = new bytes4[](2);
        _method_ids[0] = 0x0;
        _method_ids[1] = 0x0;
        address[] memory _oracles = new address[](2);
        _oracles[0] = address(0x0);
        _oracles[1] = address(0x0);

        curvePool = ICurveStableswapNG(
            curveFactory.deploy_plain_pool(
                "BOLD-USDC", "BOLDUSDC", _coins, 200, 1000000, 50000000000, 866, 0, _asset_types, _method_ids, _oracles
            )
        );

        gauge = ILiquidityGauge(curveFactory.deploy_gauge(address(curvePool)));

        curveV2GaugeRewards = new CurveV2GaugeRewards(
            address(vm.computeCreateAddress(address(this), _nonce)),
            address(bold),
            address(lqty),
            address(gauge),
            DURATION
        );

        initialInitiatives.push(address(curveV2GaugeRewards));
    }

    function run() public {
        vm.startBroadcast(privateKey);
        deployEnvironment();
        deployGovernance();
        vm.stopBroadcast();
    }
}
