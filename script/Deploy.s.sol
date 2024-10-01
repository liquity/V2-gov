// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {PoolManager, Deployers, Hooks} from "v4-core/test/utils/Deployers.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {Governance} from "../src/Governance.sol";
import {UniV4Donations} from "../src/UniV4Donations.sol";
import {CurveV2GaugeRewards} from "../src/CurveV2GaugeRewards.sol";
import {BaseHook, Hooks} from "../src/utils/BaseHook.sol";

import {UniV4DonationsImpl} from "../test/UniV4Donations.t.sol";

contract DeploymentScript is Script, Deployers {
    // Environment Constants
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant bold = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    IERC20 private constant usdc = IERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(address(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf));

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
    address private constant TOKEN = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    uint24 private constant FEE = 0;
    int24 private constant TICK_SPACING = 0;
    int24 constant MAX_TICK_SPACING = 32767;

    // CurveV2GaugeRewards Constants
    uint256 private constant DURATION = 7 days;

    Governance private governance;
    address[] private initialInitiatives;

    UniV4Donations private uniV4Donations =
        UniV4Donations(address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)));

    CurveV2GaugeRewards private curveV2GaugeRewards;

    ICurveStableswapNG private curvePool;
    ILiquidityGauge private gauge;

    function setUp() public {}

    function deployGovernance() private {
        governance = new Governance(
            address(lqty),
            address(bold),
            stakingV1,
            address(bold),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
    }

    function deployUniV4Donations(uint256 _nonce) private {
        manager = new PoolManager(500000);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        UniV4DonationsImpl impl = new UniV4DonationsImpl(
            address(vm.computeCreateAddress(address(this), _nonce)),
            address(bold),
            address(lqty),
            block.timestamp,
            EPOCH_DURATION,
            address(manager),
            address(usdc),
            400,
            MAX_TICK_SPACING,
            BaseHook(address(uniV4Donations))
        );

        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(uniV4Donations), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(uniV4Donations), slot, vm.load(address(impl), slot));
            }
        }

        initialInitiatives.push(address(uniV4Donations));
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
        // vm.broadcast();

        deployUniV4Donations(vm.getNonce(address(this)) + 2);
        deployCurveV2GaugeRewards(vm.getNonce(address(this)) + 1);
        deployGovernance();

        // vm.stopBroadcast();
    }
}
