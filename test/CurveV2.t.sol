// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
// import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ICurveStableswapFactoryNG} from "../src/interfaces/ICurveStableswapFactoryNG.sol";
import {ICurveStableswapNG} from "../src/interfaces/ICurveStableswapNG.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";

import {CurveV2GaugeRewards} from "../src/CurveV2GaugeRewards.sol";
import {Governance} from "../src/Governance.sol";
import {WAD, PermitParams} from "../src/utils/Types.sol";

interface ILQTY {
    function domainSeparator() external view returns (bytes32);
}

contract CurveV2Test is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    IERC20 private constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    ICurveStableswapFactoryNG private constant curveFactory =
        ICurveStableswapFactoryNG(address(0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf));

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;
    ICurveStableswapNG private curvePool;
    ILiquidityGauge private gauge;
    CurveV2GaugeRewards private curveV2GaugeRewards;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        address[] memory _coins = new address[](2);
        _coins[0] = address(lusd);
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
            address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(lusd),
            address(gauge),
            604800
        );

        initialInitiatives = new address[](1);
        initialInitiatives[0] = address(curveV2GaugeRewards);

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );

        vm.startPrank(curveFactory.admin());
        gauge.add_reward(address(lusd), address(curveV2GaugeRewards));
        vm.stopPrank();

        vm.startPrank(lusdHolder);

        lusd.approve(address(curvePool), type(uint256).max);
        usdc.approve(address(curvePool), type(uint256).max);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 3000e18;
        _amounts[1] = 3000e6;

        curvePool.add_liquidity(_amounts, 5998200000000000000000);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(curveV2GaugeRewards), 1000e18);
        vm.stopPrank();
    }

    function test_main() public {
        curveV2GaugeRewards.depositIntoGauge();
    }
}
