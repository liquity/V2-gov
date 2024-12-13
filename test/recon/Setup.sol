// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {MockERC20Tester} from "../mocks/MockERC20Tester.sol";
import {MockStakingV1} from "../mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "../mocks/MockStakingV1Deployer.sol";
import {Governance} from "src/Governance.sol";
import {BribeInitiative} from "../../src/BribeInitiative.sol";
import {IBribeInitiative} from "../../src/interfaces/IBribeInitiative.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";

abstract contract Setup is BaseSetup, MockStakingV1Deployer {
    Governance governance;
    MockStakingV1 internal stakingV1;
    MockERC20Tester internal lqty;
    MockERC20Tester internal lusd;
    IBribeInitiative internal initiative1;

    address internal user = address(this);
    address internal user2 = address(0x537C8f3d3E18dF5517a58B3fB9D9143697996802); // derived using makeAddrAndKey
    address internal userProxy;
    address[] internal users;
    address[] internal deployedInitiatives;
    uint256 internal user2Pk = 23868421370328131711506074113045611601786642648093516849953535378706721142721; // derived using makeAddrAndKey
    bool internal claimedTwice;
    bool internal unableToClaim;

    uint256 internal constant REGISTRATION_FEE = 1e18;
    uint256 internal constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 internal constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint256 internal constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint256 internal constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 internal constant MIN_CLAIM = 500e18;
    uint256 internal constant MIN_ACCRUAL = 1000e18;
    uint256 internal constant EPOCH_DURATION = 604800;
    uint256 internal constant EPOCH_VOTING_CUTOFF = 518400;

    uint256 magnifiedStartTS;

    function setup() internal virtual override {
        vm.warp(block.timestamp + EPOCH_DURATION * 4); // Somehow Medusa goes back after the constructor
        // Random TS that is realistic
        users.push(user);
        users.push(user2);

        (stakingV1, lqty, lusd) = deployMockStakingV1();

        uint256 initialMintAmount = type(uint88).max;
        lqty.mint(user, initialMintAmount);
        lqty.mint(user2, initialMintAmount);
        lusd.mint(user, initialMintAmount);

        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd), // bold
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                // backdate by 2 epochs to ensure new initiatives can be registered from the start
                epochStart: uint256(block.timestamp - 2 * EPOCH_DURATION),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            deployedInitiatives // no initial initiatives passed in because don't have cheatcodes for calculating address where gov will be deployed
        );

        // deploy proxy so user can approve it
        userProxy = governance.deployUserProxy();
        lqty.approve(address(userProxy), initialMintAmount);
        lusd.approve(address(userProxy), initialMintAmount);

        // approve governance for user's tokens
        lqty.approve(address(governance), initialMintAmount);
        lusd.approve(address(governance), initialMintAmount);

        // register one of the initiatives, leave the other for registering/unregistering via TargetFunction
        initiative1 = IBribeInitiative(address(new BribeInitiative(address(governance), address(lusd), address(lqty))));
        deployedInitiatives.push(address(initiative1));

        governance.registerInitiative(address(initiative1));

        magnifiedStartTS = uint256(block.timestamp) * uint256(1e18);
    }

    function _getDeployedInitiative(uint8 index) internal view returns (address initiative) {
        return deployedInitiatives[index % deployedInitiatives.length];
    }

    function _getClampedTokenBalance(address token, address holder) internal view returns (uint256 balance) {
        return IERC20(token).balanceOf(holder);
    }

    function _getRandomUser(uint8 index) internal view returns (address randomUser) {
        return users[index % users.length];
    }

    function _getInitiativeStatus(address) internal returns (uint256) {
        (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(_getDeployedInitiative(0));
        return uint256(status);
    }
}
