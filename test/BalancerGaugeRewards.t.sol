// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILiquidityGauge} from "./../src/interfaces/ILiquidityGauge.sol";
import {
    ILiquidityGaugeFactory
} from "./../src/interfaces/ILiquidityGaugeFactory.sol";
import {IBasicAuthorizer} from "./../src/interfaces/IBasicAuthorizer.sol";
import {IAuthorizerAdaptor} from "./../src/interfaces/IAuthorizerAdaptor.sol";

import {BalancerGaugeRewards} from "../src/BalancerGaugeRewards.sol";
import {Governance} from "../src/Governance.sol";

contract ForkedBalancerGaugeRewardsTest is Test {
    IERC20 private constant lqty =
        IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd =
        IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    IERC20 private constant usdc =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant stakingV1 =
        address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user =
        address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder =
        address(0x6f71fc3925605F06672409c71844eaD4B700Af5F);
    ILiquidityGaugeFactory private constant gaugeFactory =
        ILiquidityGaugeFactory(
            address(0xf1665E19bc105BE4EDD3739F88315cC699cc5b65)
        );
    IERC20 private constant balancerPool =
        IERC20(address(0xc334299aEf610Fc79da129A920317B2BDBe2557E));
    address private constant DAO =
        address(0x10A19e7eE7d7F8a52822f6817de8ea18204F2e4f);
    IBasicAuthorizer private constant authorizer =
        IBasicAuthorizer(address(0xA331D84eC860Bf466b4CdCcFb4aC09a1B43F3aE6));
    IAuthorizerAdaptor private constant authorizerAdaptorEntrypoint =
        IAuthorizerAdaptor(address(0xf5dECDB1f3d1ee384908Fbe16D2F0348AE43a9eA));

    bytes32 private constant ADD_REWARDS_ACTION_ID =
        0x3bf29175652a3f0fac5abb715d0b7fe2e7b597e2e2eff555dac6b21a20a7c83e;

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;
    ILiquidityGauge private gauge;
    BalancerGaugeRewards private balancerGaugeRewards;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 24836000);

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            epochStart: uint32(block.timestamp),
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            config,
            address(this),
            initialInitiatives
        );

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

        // Relative weight cap of 10%.
        gauge = ILiquidityGauge(
            gaugeFactory.create(address(balancerPool), 10e16)
        );

        balancerGaugeRewards = new BalancerGaugeRewards(
            // address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
            address(governance),
            address(lusd),
            address(lqty),
            address(gauge),
            604800
        );

        initialInitiatives.push(address(balancerGaugeRewards));
        governance.registerInitialInitiatives(initialInitiatives);

        vm.startPrank(DAO);
        authorizer.grantRole(ADD_REWARDS_ACTION_ID, DAO);
        // call gauge.add_reward(address(lusd), address(balancerGaugeRewards));
        authorizerAdaptorEntrypoint.performAction(
            address(gauge),
            abi.encodeWithSelector(
                ILiquidityGauge.add_reward.selector,
                address(lusd),
                address(balancerGaugeRewards)
            )
        );
        vm.stopPrank();
    }

    function test_claimAndDepositIntoGaugeFuzz(uint256 amount) public {
        amount = bound(amount, 1, lusd.balanceOf(lusdHolder));
        deal(address(lusd), address(governance), amount);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        lusd.transfer(address(balancerGaugeRewards), amount);

        assertEq(lusd.balanceOf(address(balancerGaugeRewards)), amount);
        balancerGaugeRewards.onClaimForInitiative(0, amount);
        assertEq(
            lusd.balanceOf(address(balancerGaugeRewards)),
            0,
            "Balancer gauge rewards balance is not zero"
        );
        assertEq(
            lusd.balanceOf(address(gauge)),
            amount,
            "Gauge balance does not match amount transferred"
        );
    }

    function test_claimAndDepositIntoGaugeFuzzAboveContractBalance(uint256 contractBalance, uint256 extra) public {
        contractBalance = bound(contractBalance, 1, lusd.balanceOf(lusdHolder));
        extra = bound(extra, 1e18, 100e18);
        deal(address(lusd), address(governance), contractBalance);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        lusd.transfer(address(balancerGaugeRewards), contractBalance);

        assertEq(lusd.balanceOf(address(balancerGaugeRewards)), contractBalance);
        balancerGaugeRewards.onClaimForInitiative(0, contractBalance + extra);
        assertEq(
            lusd.balanceOf(address(balancerGaugeRewards)),
            0,
            "Balancer gauge rewards balance is not zero"
        );
        assertEq(
            lusd.balanceOf(address(gauge)),
            contractBalance,
            "Gauge balance does not match amount transferred"
        );
    }

    function test_claimAndDepositIntoGaugeFuzzBelowContractBalance(uint256 contractBalance, uint256 amount) public {
        contractBalance = bound(contractBalance, 1, lusd.balanceOf(lusdHolder));
        amount = bound(amount, 0, contractBalance - 1);
        deal(address(lusd), address(governance), contractBalance);

        // Pretend a Proposal has passed
        vm.startPrank(address(governance));
        lusd.transfer(address(balancerGaugeRewards), contractBalance);

        assertEq(lusd.balanceOf(address(balancerGaugeRewards)), contractBalance);
        balancerGaugeRewards.onClaimForInitiative(0, amount);
        assertEq(
            lusd.balanceOf(address(balancerGaugeRewards)),
            contractBalance - amount,
            "Balancer gauge rewards balance is not zero"
        );
        assertEq(
            lusd.balanceOf(address(gauge)),
            amount,
            "Gauge balance does not match amount transferred"
        );
    }
}
