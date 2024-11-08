// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILQTY} from "../src/interfaces/ILQTY.sol";

import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {UserProxy} from "../src/UserProxy.sol";

import {PermitParams} from "../src/utils/Types.sol";

import {MockInitiative} from "./mocks/MockInitiative.sol";

contract E2ETests is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint128 private constant REGISTRATION_FEE = 1e18;
    uint128 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint128 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint16 private constant REGISTRATION_WARM_UP_PERIOD = 4;
    uint16 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint128 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint88 private constant MIN_CLAIM = 500e18;
    uint88 private constant MIN_ACCRUAL = 1000e18;
    uint32 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        baseInitiative1 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative2 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative3 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
                address(lusd),
                address(lqty)
            )
        );

        initialInitiatives.push(baseInitiative1);
        initialInitiatives.push(baseInitiative2);

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint32(block.timestamp - EPOCH_DURATION),
                /// @audit KEY
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );
    }

    // forge test --match-test test_initialInitiativesCanBeVotedOnAtStart -vv
    function test_initialInitiativesCanBeVotedOnAtStart() public {
        /// @audit NOTE: In order for this to work, the constructor must set the start time a week behind
        /// This will make the initiatives work on the first epoch
        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 1e18, 0); // Doesn't work due to cool down I think

        // And for sanity, you cannot vote on new ones, they need to be added first
        deal(address(lusd), address(user), REGISTRATION_FEE);
        lusd.approve(address(governance), REGISTRATION_FEE);
        governance.registerInitiative(address(0x123123));

        vm.expectRevert();
        _allocate(address(0x123123), 1e18, 0);

        // Whereas in next week it will work
        vm.warp(block.timestamp + EPOCH_DURATION);
        _allocate(address(0x123123), 1e18, 0);
    }

    // forge test --match-test test_deregisterIsSound -vv
    function test_deregisterIsSound() public {
        // Deregistration works as follows:
        // We stop voting
        // We wait for `UNREGISTRATION_AFTER_EPOCHS`
        // The initiative is removed
        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 1e18, 0); // Doesn't work due to cool down I think

        // And for sanity, you cannot vote on new ones, they need to be added first
        deal(address(lusd), address(user), REGISTRATION_FEE);
        lusd.approve(address(governance), REGISTRATION_FEE);

        address newInitiative = address(0x123123);
        governance.registerInitiative(newInitiative);
        assertEq(uint256(Governance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative), "Cooldown");

        uint256 skipCount;

        address[] memory toAllocate = new address[](2);
        toAllocate[0] = baseInitiative1;
        toAllocate[1] = newInitiative;

        int88[] memory votes = new int88[](2);
        votes[0] = 1e18;
        votes[1] = 100;
        int88[] memory vetos = new int88[](2);

        // Whereas in next week it will work
        vm.warp(block.timestamp + EPOCH_DURATION); // 1
        ++skipCount;
        assertEq(uint256(Governance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // Cooldown on epoch Staert
        vm.warp(block.timestamp + EPOCH_DURATION); // 2
        ++skipCount;
        assertEq(uint256(Governance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(Governance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 4
        ++skipCount;
        assertEq(
            uint256(Governance.InitiativeStatus.UNREGISTERABLE), _getInitiativeStatus(newInitiative), "UNREGISTERABLE"
        );

        assertEq(skipCount, UNREGISTRATION_AFTER_EPOCHS, "Skipped exactly UNREGISTRATION_AFTER_EPOCHS");
    }

    function _deposit(uint88 amt) internal {
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), amt);
        governance.depositLQTY(amt);
    }

    function _allocate(address initiative, int88 votes, int88 vetos) internal {
        address[] memory initiativesToDeRegister = new address[](4);
        initiativesToDeRegister[0] = baseInitiative1;
        initiativesToDeRegister[1] = baseInitiative2;
        initiativesToDeRegister[2] = baseInitiative3;
        initiativesToDeRegister[3] = address(0x123123);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = votes;
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = vetos;

        governance.allocateLQTY(initiativesToDeRegister, initiatives, deltaLQTYVotes, deltaLQTYVetos);
    }

    function _allocate(address[] memory initiatives, int88[] memory votes, int88[] memory vetos) internal {
        address[] memory initiativesToDeRegister = new address[](4);
        initiativesToDeRegister[0] = baseInitiative1;
        initiativesToDeRegister[1] = baseInitiative2;
        initiativesToDeRegister[2] = baseInitiative3;
        initiativesToDeRegister[3] = address(0x123123);

        governance.allocateLQTY(initiativesToDeRegister, initiatives, votes, vetos);
    }

    function _getInitiativeStatus(address _initiative) internal returns (uint256) {
        (Governance.InitiativeStatus status,,) = governance.getInitiativeState(_initiative);
        return uint256(status);
    }
}
