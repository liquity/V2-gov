// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {PoolManager, Deployers, Hooks} from "v4-core/test/utils/Deployers.sol";
import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {UniV4Donations} from "../src/UniV4Donations.sol";
import {CurveV2GaugeRewards} from "../src/CurveV2GaugeRewards.sol";
import {Hooks} from "../src/utils/BaseHook.sol";

import {MockStakingV1} from "../test/mocks/MockStakingV1.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import "forge-std/console2.sol";

contract DeploySepoliaScript is Script, Deployers {
    address constant BOLD_ADDRESS = 0x31764dCd10FfF1514DB117e3Db84b48b30db5B43;
    // Environment Constants
    MockERC20 private lqty;
    MockERC20 private lusd;
    address private stakingV1;
    MockERC20 private usdc;

    PoolManager private constant poolManager = PoolManager(0xE8E23e97Fa135823143d6b9Cba9c699040D51F70);
    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(address(0xfb37b8D939FFa77114005e61CFc2e543d6F49A81));

    // Governance Constants
    uint128 private constant REGISTRATION_FEE = 100e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.001e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 3e18;
    uint16 private constant REGISTRATION_WARM_UP_PERIOD = 4;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.03e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    // UniV4Donations Constants
    uint256 private immutable VESTING_EPOCH_START = block.timestamp;
    uint256 private constant VESTING_EPOCH_DURATION = 7 days;
    uint24 private constant FEE = 400;
    int24 constant MAX_TICK_SPACING = 32767;

    // CurveV2GaugeRewards Constants
    uint256 private constant DURATION = 7 days;

    // Contracts
    Governance private governance;
    address[] private initialInitiatives;
    UniV4Donations private uniV4Donations;
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
        lqty = deployMockERC20("Liquity", "LQTY", 18);
        lusd = deployMockERC20("Liquity USD", "LUSD", 18);
        usdc = deployMockERC20("USD Coin", "USDC", 6);
        stakingV1 = address(new MockStakingV1(address(lqty)));
    }

    function deployGovernance() private {
        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            BOLD_ADDRESS,
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint32(block.timestamp - VESTING_EPOCH_START),
                /// @audit Ensures that `initialInitiatives` can be voted on
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
        assert(governance == uniV4Donations.governance());
    }

    function deployUniV4Donations(uint256 _nonce) private {
        address gov = address(vm.computeCreateAddress(deployer, _nonce));
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG);

        (, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C,
            // address(this),
            flags,
            type(UniV4Donations).creationCode,
            abi.encode(
                gov,
                BOLD_ADDRESS,
                address(lqty),
                block.timestamp,
                EPOCH_DURATION,
                address(poolManager),
                address(usdc),
                FEE,
                MAX_TICK_SPACING
            )
        );

        uniV4Donations = new UniV4Donations{salt: salt}(
            gov,
            BOLD_ADDRESS,
            address(lqty),
            block.timestamp,
            EPOCH_DURATION,
            address(poolManager),
            address(usdc),
            FEE,
            MAX_TICK_SPACING
        );

        initialInitiatives.push(address(uniV4Donations));
    }

    function deployCurveV2GaugeRewards(uint256 _nonce) private {
        address[] memory _coins = new address[](2);
        _coins[0] = BOLD_ADDRESS;
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
            BOLD_ADDRESS,
            address(lqty),
            address(gauge),
            DURATION
        );

        initialInitiatives.push(address(curveV2GaugeRewards));
    }

    function run() public {
        vm.startBroadcast(privateKey);
        deployEnvironment();
        deployUniV4Donations(nonce + 8);
        deployGovernance();
        vm.stopBroadcast();
    }
}
