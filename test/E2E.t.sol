// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";

contract ForkedE2ETests is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint256 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            epochStart: uint256(block.timestamp - EPOCH_DURATION),
            /// @audit KEY
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance(
            address(lqty), address(lusd), stakingV1, address(lusd), config, address(this), new address[](0)
        );

        baseInitiative1 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        baseInitiative2 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        baseInitiative3 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));

        initialInitiatives.push(baseInitiative1);
        initialInitiatives.push(baseInitiative2);

        governance.registerInitialInitiatives(initialInitiatives);
    }

    function test_initialInitiativesCanBeVotedOnAtStart() public {
        /// @audit NOTE: In order for this to work, the constructor must set the start time a week behind
        /// This will make the initiatives work immediately after deployment, on the second epoch
        vm.startPrank(user);
        _deposit(1000e18);

        // Check that we can vote right after deployment
        console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 1e18, 0);
        _reset(baseInitiative1);

        // Registration not allowed initially, so skip one epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        deal(address(lusd), address(user), REGISTRATION_FEE);
        lusd.approve(address(governance), REGISTRATION_FEE);
        governance.registerInitiative(address(0x123123));

        // You cannot immediately vote on new ones
        vm.expectRevert();
        _allocate(address(0x123123), 1e18, 0);

        // Whereas in next epoch it will work
        vm.warp(block.timestamp + EPOCH_DURATION);
        _allocate(address(0x123123), 1e18, 0);
    }

    function test_canYouVoteWith100MLNLQTY() public {
        deal(address(lqty), user, 100_000_000e18);
        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(100_000_000e18);

        //console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 100_000_000e18, 0);
    }

    function test_canYouVoteWith100MLNLQTY_after_10_years() public {
        deal(address(lqty), user, 100_000_000e18);
        deal(address(lusd), user, 1e18);

        vm.startPrank(user);
        lusd.approve(address(governance), 1e18);

        // Check that we can vote on the first epoch, right after deployment
        _deposit(100_000_000e18);

        vm.warp(block.timestamp + 365 days * 10);
        address newInitiative = address(0x123123);
        governance.registerInitiative(newInitiative);

        vm.warp(block.timestamp + EPOCH_DURATION);

        //console.log("epoch", governance.epoch());
        _allocate(newInitiative, 100_000_000e18, 0);
    }

    function test_noVetoGriefAtEpochOne() public {
        /// @audit NOTE: In order for this to work, the constructor must set the start time a week behind
        /// This will make the initiatives work on the first epoch
        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 0, 1e18); // Doesn't work due to cool down I think

        vm.expectRevert();
        governance.unregisterInitiative(baseInitiative1);

        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.unregisterInitiative(baseInitiative1);
    }

    function test_deregisterIsSound() public {
        // Deregistration works as follows:
        // We stop voting
        // We wait for `UNREGISTRATION_AFTER_EPOCHS`
        // The initiative is removed
        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        console.log("epoch", governance.epoch());
        _allocate(baseInitiative1, 1e18, 0);

        // And for sanity, you cannot vote on new ones, they need to be added first
        deal(address(lusd), address(user), REGISTRATION_FEE);
        lusd.approve(address(governance), REGISTRATION_FEE);

        // Registration not allowed initially, so skip one epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        address newInitiative = address(0x123123);
        governance.registerInitiative(newInitiative);
        assertEq(uint256(IGovernance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative), "Cooldown");

        uint256 skipCount;

        // WARM_UP at 0

        // Whereas in next week it will work
        vm.warp(block.timestamp + EPOCH_DURATION); // 1
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // Cooldown on epoch Staert
        vm.warp(block.timestamp + EPOCH_DURATION); // 2
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 4
        ++skipCount;
        assertEq(
            uint256(IGovernance.InitiativeStatus.UNREGISTERABLE), _getInitiativeStatus(newInitiative), "UNREGISTERABLE"
        );

        /// 4 + 1 ??
        assertEq(skipCount, UNREGISTRATION_AFTER_EPOCHS + 1, "Skipped exactly UNREGISTRATION_AFTER_EPOCHS");
    }

    // forge test --match-test test_unregisterWorksCorrectlyEvenAfterXEpochs -vv
    function test_unregisterWorksCorrectlyEvenAfterXEpochs(uint8 epochsInFuture) public {
        // Registration starts working after one epoch, so fast-forward at least one EPOCH_DURATION
        vm.warp(block.timestamp + (uint32(1) + epochsInFuture) * EPOCH_DURATION);

        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        // And for sanity, you cannot vote on new ones, they need to be added first
        deal(address(lusd), address(user), REGISTRATION_FEE * 2);
        lusd.approve(address(governance), REGISTRATION_FEE * 2);

        address newInitiative = address(0x123123);
        address newInitiative2 = address(0x1231234);
        governance.registerInitiative(newInitiative);
        governance.registerInitiative(newInitiative2);
        assertEq(uint256(IGovernance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative), "Cooldown");
        assertEq(uint256(IGovernance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative2), "Cooldown");

        uint256 skipCount;

        // SPEC:
        // Initiative is at WARM_UP at registration epoch

        // The following EPOCH it can be voted on, it has status SKIP

        vm.warp(block.timestamp + EPOCH_DURATION); // 1
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        _allocate(newInitiative2, 1e18, 0);

        // 2nd Week of SKIP

        // Cooldown on epoch Staert
        vm.warp(block.timestamp + EPOCH_DURATION); // 2
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // 3rd Week of SKIP

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // 4th Week of SKIP | If it doesn't get any rewards it will be UNREGISTERABLE

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        vm.warp(block.timestamp + EPOCH_DURATION); // 4
        ++skipCount;
        assertEq(
            uint256(IGovernance.InitiativeStatus.UNREGISTERABLE), _getInitiativeStatus(newInitiative), "UNREGISTERABLE"
        );

        /// It was SKIP for 4 EPOCHS, it is now UNREGISTERABLE
        assertEq(skipCount, UNREGISTRATION_AFTER_EPOCHS + 1, "Skipped exactly UNREGISTRATION_AFTER_EPOCHS");
    }

    function test_unregisterWorksCorrectlyEvenAfterXEpochs_andCanBeSavedAtLast(uint8 epochsInFuture) public {
        // Registration starts working after one epoch, so fast-forward at least one EPOCH_DURATION
        vm.warp(block.timestamp + (uint32(1) + epochsInFuture) * EPOCH_DURATION);

        vm.startPrank(user);
        // Check that we can vote on the first epoch, right after deployment
        _deposit(1000e18);

        // And for sanity, you cannot vote on new ones, they need to be added first
        deal(address(lusd), address(user), REGISTRATION_FEE * 2);
        lusd.approve(address(governance), REGISTRATION_FEE * 2);

        address newInitiative = address(0x123123);
        address newInitiative2 = address(0x1231234);
        governance.registerInitiative(newInitiative);
        governance.registerInitiative(newInitiative2);
        assertEq(uint256(IGovernance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative), "Cooldown");
        assertEq(uint256(IGovernance.InitiativeStatus.WARM_UP), _getInitiativeStatus(newInitiative2), "Cooldown");

        uint256 skipCount;

        // SPEC:
        // Initiative is at WARM_UP at registration epoch

        // The following EPOCH it can be voted on, it has status SKIP

        vm.warp(block.timestamp + EPOCH_DURATION); // 1
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        _allocate(newInitiative2, 1e18, 0);

        // 2nd Week of SKIP

        // Cooldown on epoch Staert
        vm.warp(block.timestamp + EPOCH_DURATION); // 2
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // 3rd Week of SKIP

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // 4th Week of SKIP | If it doesn't get any rewards it will be UNREGISTERABLE

        vm.warp(block.timestamp + EPOCH_DURATION); // 3
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.SKIP), _getInitiativeStatus(newInitiative), "SKIP");

        // Allocating to it, saves it
        _reset(newInitiative2);
        _allocate(newInitiative, 1e18, 0);

        vm.warp(block.timestamp + EPOCH_DURATION); // 4
        ++skipCount;
        assertEq(uint256(IGovernance.InitiativeStatus.CLAIMABLE), _getInitiativeStatus(newInitiative), "UNREGISTERABLE");
    }

    function _deposit(uint256 amt) internal {
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), amt);
        governance.depositLQTY(amt);
    }

    function _allocate(address initiative, int256 votes, int256 vetos) internal {
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory absoluteLQTYVotes = new int256[](1);
        absoluteLQTYVotes[0] = votes;
        int256[] memory absoluteLQTYVetos = new int256[](1);
        absoluteLQTYVetos[0] = vetos;

        governance.allocateLQTY(initiativesToReset, initiatives, absoluteLQTYVotes, absoluteLQTYVetos);
    }

    function _allocate(address[] memory initiatives, int256[] memory votes, int256[] memory vetos) internal {
        address[] memory initiativesToReset;
        governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
    }

    function _reset(address initiative) internal {
        address[] memory initiativesToReset = new address[](1);
        initiativesToReset[0] = initiative;
        governance.resetAllocations(initiativesToReset, false);
    }

    function _getInitiativeStatus(address _initiative) internal returns (uint256) {
        (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(_initiative);
        return uint256(status);
    }
}
