// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {IERC20Errors} from "openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {ILUSD} from "../src/interfaces/ILUSD.sol";
import {ILQTY} from "../src/interfaces/ILQTY.sol";
import {ILQTYStaking} from "../src/interfaces/ILQTYStaking.sol";

import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {UserProxy} from "../src/UserProxy.sol";

import {PermitParams} from "../src/utils/Types.sol";

import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockInitiative} from "./mocks/MockInitiative.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";
import "./constants.sol";

contract GovernanceTester is Governance {
    constructor(
        address _lqty,
        address _lusd,
        address _stakingV1,
        address _bold,
        Configuration memory _config,
        address _owner,
        address[] memory _initiatives
    ) Governance(_lqty, _lusd, _stakingV1, _bold, _config, _owner, _initiatives) {}

    function tester_setVotesSnapshot(VoteSnapshot calldata _votesSnapshot) external {
        votesSnapshot = _votesSnapshot;
    }

    function tester_setVotesForInitiativeSnapshot(
        address _initiative,
        InitiativeVoteSnapshot calldata _votesForInitiativeSnapshot
    ) external {
        votesForInitiativeSnapshot[_initiative] = _votesForInitiativeSnapshot;
    }

    function tester_setBoldAccrued(uint256 _boldAccrued) external {
        boldAccrued = _boldAccrued;
    }
}

abstract contract GovernanceTest is Test {
    using Strings for uint256;

    ILQTY internal lqty;
    ILUSD internal lusd;
    ILQTYStaking internal stakingV1;

    address internal constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address internal constant user2 = address(0x10C9cff3c4Faa8A60cB8506a7A99411E6A199038);
    address internal constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant UNREGISTRATION_THRESHOLD_FACTOR = 4e18;
    uint256 private constant UNREGISTRATION_AFTER_EPOCHS = 4;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint32 private constant EPOCH_VOTING_CUTOFF = 518400;

    GovernanceTester private governance;
    address[] private initialInitiatives;

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function _expectInsufficientAllowance() internal virtual;
    function _expectInsufficientBalance() internal virtual;

    // When both allowance and balance are insufficient, LQTY fails on insufficient balance, unlike recent OZ ERC20
    function _expectInsufficientAllowanceAndBalance() internal virtual;

    function setUp() public virtual {
        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: MIN_CLAIM,
            minAccrual: MIN_ACCRUAL,
            epochStart: uint256(block.timestamp),
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new GovernanceTester(
            address(lqty), address(lusd), address(stakingV1), address(lusd), config, address(this), new address[](0)
        );

        baseInitiative1 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        baseInitiative2 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        baseInitiative3 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));

        initialInitiatives.push(baseInitiative1);
        initialInitiatives.push(baseInitiative2);
        governance.registerInitialInitiatives(initialInitiatives);
    }

    // forge test --match-test test_depositLQTY_withdrawLQTY -vv
    function test_depositLQTY_withdrawLQTY() public {
        uint256 timeIncrease = 86400 * 30;
        vm.warp(block.timestamp + timeIncrease);

        vm.startPrank(user);

        // should revert with a 0 amount
        vm.expectRevert("Governance: zero-lqty-amount");
        governance.depositLQTY(0);

        // should revert if the `_lqtyAmount` > `lqty.allowance(msg.sender, userProxy)`
        _expectInsufficientAllowance();
        governance.depositLQTY(1e18);

        // should revert if the `_lqtyAmount` > `lqty.balanceOf(msg.sender)`
        _expectInsufficientAllowanceAndBalance();
        governance.depositLQTY(1e26);

        uint256 lqtyDeposit = 2e18;

        // should not revert if the user doesn't have a UserProxy deployed yet
        address userProxy = governance.deriveUserProxyAddress(user);
        lqty.approve(address(userProxy), lqtyDeposit);
        // vm.expectEmit("DepositLQTY", abi.encode(user, 1e18));
        // deploy and deposit 2 LQTY
        governance.depositLQTY(lqtyDeposit);
        assertEq(UserProxy(payable(userProxy)).staked(), lqtyDeposit);
        (uint256 unallocatedLQTY, uint256 unallocatedOffset,,) = governance.userStates(user);
        assertEq(unallocatedLQTY, lqtyDeposit);

        uint256 expectedOffset1 = block.timestamp * lqtyDeposit;
        // first deposit should have an unallocated offset of deposit * block.timestamp
        assertEq(unallocatedOffset, expectedOffset1);

        vm.warp(block.timestamp + timeIncrease);

        // Deposit again
        lqty.approve(address(userProxy), lqtyDeposit);
        governance.depositLQTY(lqtyDeposit);
        assertEq(UserProxy(payable(userProxy)).staked(), lqtyDeposit * 2);
        (unallocatedLQTY, unallocatedOffset,,) = governance.userStates(user);
        assertEq(unallocatedLQTY, lqtyDeposit * 2);

        uint256 expectedOffset2 = expectedOffset1 + block.timestamp * lqtyDeposit;
        // subsequent deposits should result in an increased unallocated offset
        assertEq(unallocatedOffset, expectedOffset2, "unallocated offset");

        // withdraw half of LQTY
        vm.warp(block.timestamp + timeIncrease);

        vm.startPrank(address(this));
        vm.expectRevert("Governance: user-proxy-not-deployed");
        governance.withdrawLQTY(lqtyDeposit);
        vm.stopPrank();

        vm.startPrank(user);

        governance.withdrawLQTY(lqtyDeposit);
        assertEq(UserProxy(payable(userProxy)).staked(), lqtyDeposit);
        (unallocatedLQTY, unallocatedOffset,,) = governance.userStates(user);
        assertEq(unallocatedLQTY, lqtyDeposit);
        // Withdrawing half of the LQTY should also halve the offset, i.e. withdraw "proportionally" from all past deposits
        assertEq(unallocatedOffset, expectedOffset2 / 2, "unallocated offset2");

        // withdraw remaining LQTY
        governance.withdrawLQTY(lqtyDeposit);
        assertEq(UserProxy(payable(userProxy)).staked(), 0);
        (unallocatedLQTY, unallocatedOffset,,) = governance.userStates(user);
        assertEq(unallocatedLQTY, 0);
        assertEq(unallocatedOffset, 0, "unallocated offset2");

        vm.stopPrank();
    }

    function test_depositLQTYViaPermit() public {
        uint256 timeIncrease = 86400 * 30;
        vm.warp(block.timestamp + timeIncrease);

        vm.startPrank(user);
        VmSafe.Wallet memory wallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        lqty.transfer(wallet.addr, 1e18);
        vm.stopPrank();
        vm.startPrank(wallet.addr);

        // check address
        address userProxy = governance.deriveUserProxyAddress(wallet.addr);

        PermitParams memory permitParams = PermitParams({
            owner: wallet.addr,
            spender: address(userProxy),
            value: 1e18,
            deadline: block.timestamp + 86400,
            v: 0,
            r: "",
            s: ""
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wallet.privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ILQTY(address(lqty)).domainSeparator(),
                    keccak256(
                        abi.encode(
                            0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9,
                            permitParams.owner,
                            permitParams.spender,
                            permitParams.value,
                            0,
                            permitParams.deadline
                        )
                    )
                )
            )
        );

        permitParams.v = v;
        permitParams.r = r;

        _expectInsufficientAllowance();
        governance.depositLQTYViaPermit(1e18, permitParams);

        permitParams.s = s;

        vm.startPrank(address(this));
        vm.expectRevert("UserProxy: owner-not-sender");
        governance.depositLQTYViaPermit(1e18, permitParams);
        vm.stopPrank();

        vm.startPrank(wallet.addr);

        _expectInsufficientAllowanceAndBalance();
        governance.depositLQTYViaPermit(1e26, permitParams);

        // deploy and deposit 1 LQTY
        governance.depositLQTYViaPermit(1e18, permitParams);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (uint256 unallocatedLQTY, uint256 unallocatedOffset,,) = governance.userStates(wallet.addr);
        assertEq(unallocatedLQTY, 1e18);
        assertEq(unallocatedOffset, 1e18 * block.timestamp);
    }

    function test_claimFromStakingV1() public {
        uint256 timeIncrease = 86400 * 30;
        vm.warp(block.timestamp + timeIncrease);

        vm.expectRevert("Governance: user-proxy-not-deployed");
        governance.claimFromStakingV1(address(this));

        vm.startPrank(user);

        // check address
        address userProxy = governance.deriveUserProxyAddress(user);

        // deploy and deposit 1 LQTY
        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);

        vm.warp(block.timestamp + timeIncrease);

        governance.claimFromStakingV1(user);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
    }

    // should return the correct epoch for a given block.timestamp
    function test_epoch() public {
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 7 days - 1);
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 1);
        assertEq(governance.epoch(), 2);

        vm.warp(block.timestamp + 3653 days - 7 days);
        assertEq(governance.epoch(), 522); // number of weeks + 1
    }

    // should not revert under any block.timestamp >= EPOCH_START
    function test_epoch_fuzz(uint32 _timestamp) public {
        vm.warp(governance.EPOCH_START() + _timestamp);
        governance.epoch();
    }

    // should return the correct epoch start timestamp for a given block.timestamp
    function test_epochStart() public {
        assertEq(governance.epochStart(), block.timestamp);
        vm.warp(block.timestamp + 1);
        assertEq(governance.epochStart(), block.timestamp - 1);
    }

    // should not revert under any block.timestamp >= EPOCH_START
    function test_epochStart_fuzz(uint32 _timestamp) public {
        vm.warp(governance.EPOCH_START() + _timestamp);
        governance.epochStart();
    }

    // should return the correct number of seconds elapsed within an epoch for a given block.timestamp
    function test_secondsWithinEpoch() public {
        assertEq(governance.secondsWithinEpoch(), 0);
        vm.warp(block.timestamp + 1);
        assertEq(governance.secondsWithinEpoch(), 1);
        vm.warp(block.timestamp + EPOCH_DURATION - 1);
        assertEq(governance.secondsWithinEpoch(), 0);
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(governance.secondsWithinEpoch(), 0);
        vm.warp(block.timestamp + 1);
        assertEq(governance.secondsWithinEpoch(), 1);
    }

    // should not revert under any block.timestamp
    function test_secondsWithinEpoch_fuzz(uint32 _timestamp) public {
        vm.warp(governance.EPOCH_START() + _timestamp);
        governance.secondsWithinEpoch();
    }

    // should not revert under any input
    function test_lqtyToVotes(uint88 _lqtyAmount, uint32 _currentTimestamp, uint256 _offset) public {
        governance.lqtyToVotes(_lqtyAmount, _currentTimestamp, _offset);
    }

    function test_getLatestVotingThreshold() public {
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // is 0 when the previous epochs votes are 0
        assertEq(governance.getLatestVotingThreshold(), 0);

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, governance.epoch());
        governance.tester_setVotesSnapshot(snapshot);

        uint256 boldAccrued = 1000e18;
        governance.tester_setBoldAccrued(boldAccrued);

        assertEq(governance.getLatestVotingThreshold(), MIN_CLAIM / 1000);

        // check that votingThreshold is 4% of votes of previous epoch
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: 10e18,
                minAccrual: 10e18,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        snapshot = IGovernance.VoteSnapshot(10000e18, governance.epoch());
        governance.tester_setVotesSnapshot(snapshot);

        boldAccrued = 1000e18;
        governance.tester_setBoldAccrued(boldAccrued);

        assertEq(governance.getLatestVotingThreshold(), 10000e18 * 0.04);
    }

    // should not revert under any state
    function test_calculateVotingThreshold_fuzz(
        uint256 _votes,
        uint256 _forEpoch,
        uint256 _boldAccrued,
        uint256 _votingThresholdFactor,
        uint256 _minClaim
    ) public {
        _votes = bound(_votes, 0, type(uint128).max);
        _forEpoch = bound(_forEpoch, 0, type(uint16).max);
        _boldAccrued = bound(_boldAccrued, 0, 1e9 ether);
        _votingThresholdFactor = bound(_votingThresholdFactor, 0, 1 ether - 1);
        _minClaim = bound(_minClaim, 0, 1e9 ether);

        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: _votingThresholdFactor,
                minClaim: _minClaim,
                minAccrual: type(uint256).max,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(_votes, _forEpoch);
        governance.tester_setVotesSnapshot(snapshot);
        governance.tester_setBoldAccrued(_boldAccrued);

        governance.getLatestVotingThreshold();
    }

    function test_registerInitiative() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        vm.expectRevert("Governance: registration-not-yet-enabled");
        governance.registerInitiative(baseInitiative3);

        // Registration not allowed before epoch #3
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);
        assertEq(governance.epoch(), 3, "We should be in epoch #3");

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, governance.epoch());
        governance.tester_setVotesSnapshot(snapshot);

        // should revert if the `REGISTRATION_FEE` > `lusd.balanceOf(msg.sender)`
        _expectInsufficientAllowanceAndBalance();
        governance.registerInitiative(baseInitiative3);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 2e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 2e18);

        // should revert if the registrant doesn't have enough voting power
        vm.expectRevert("Governance: insufficient-lqty");
        governance.registerInitiative(baseInitiative3);

        // should revert if the `REGISTRATION_FEE` > `lusd.allowance(msg.sender, governance)`
        _expectInsufficientAllowance();
        governance.depositLQTY(1e18);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + EPOCH_DURATION);

        // should revert if `_initiative` is zero
        vm.expectRevert("Governance: zero-address");
        governance.registerInitiative(address(0));

        governance.registerInitiative(baseInitiative3);
        uint256 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        // should revert if the initiative was already registered
        vm.expectRevert("Governance: initiative-already-registered");
        governance.registerInitiative(baseInitiative3);

        vm.stopPrank();
    }

    function test_RegistrationFeesAreUsedAsRewardInNextEpoch() external {
        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: REGISTRATION_FEE,
            registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
            unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
            unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
            votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
            minClaim: 0, // ensure REGISTRATION_FEE is enough to make a claim
            minAccrual: 0,
            epochStart: uint256(block.timestamp) - EPOCH_DURATION, // ensure initial initiative can be voted on
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new GovernanceTester(
            address(lqty), address(lusd), address(stakingV1), address(lusd), config, address(this), new address[](0)
        );

        baseInitiative1 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));
        baseInitiative2 = address(new BribeInitiative(address(governance), address(lusd), address(lqty)));

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        governance.registerInitialInitiatives(initiatives);

        // Send user enough LUSD to register a new initiative
        vm.prank(lusdHolder);
        lusd.transfer(user, REGISTRATION_FEE);

        vm.startPrank(user);
        {
            uint256 lqtyAmount = 1 ether;

            lqty.approve(governance.deriveUserProxyAddress(user), lqtyAmount);
            governance.depositLQTY(lqtyAmount);

            address[] memory initiativesToReset; // left empty
            int256[] memory votes = new int256[](1);
            int256[] memory vetos = new int256[](1); // left zero

            // User votes some LQTY on baseInitiative1
            votes[0] = int256(lqtyAmount);
            governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);

            // Jump into next epoch
            vm.warp(governance.epochStart() + EPOCH_DURATION + 6 hours);

            // Register new initiative
            lusd.approve(address(governance), REGISTRATION_FEE);
            governance.registerInitiative(baseInitiative2);
        }
        vm.stopPrank();

        governance.claimForInitiative(baseInitiative1);
        assertEqDecimal(lusd.balanceOf(baseInitiative1), 0, 18, "baseInitiative1 shouldn't have received LUSD yet");

        // One epoch later
        vm.warp(block.timestamp + EPOCH_DURATION);

        governance.claimForInitiative(baseInitiative1);
        assertEqDecimal(
            lusd.balanceOf(baseInitiative1),
            REGISTRATION_FEE,
            18,
            "baseInitiative1 should have received the registration fee"
        );
    }

    // forge test --match-test test_unregisterInitiative -vv
    function test_unregisterInitiative() public {
        vm.startPrank(lusdHolder);
        lusd.transfer(user, 1e18);
        vm.stopPrank();

        vm.startPrank(user);

        // should revert if the initiative isn't registered
        vm.expectRevert("Governance: cannot-unregister-initiative");
        governance.unregisterInitiative(baseInitiative3);

        // Registration not allowed before epoch #3
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);
        assertEq(governance.epoch(), 3, "We should be in epoch #3");

        lusd.approve(address(governance), 1e18);
        governance.registerInitiative(baseInitiative3);

        // should revert if the initiative is still in the registration warm up period
        vm.expectRevert("Governance: cannot-unregister-initiative");
        /// @audit should fail due to not waiting enough time
        governance.unregisterInitiative(baseInitiative3);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // should revert if the initiative is still active or the vetos don't meet the threshold
        vm.expectRevert("Governance: cannot-unregister-initiative");
        governance.unregisterInitiative(baseInitiative3);

        vm.warp(block.timestamp + EPOCH_DURATION * UNREGISTRATION_AFTER_EPOCHS);

        governance.unregisterInitiative(baseInitiative3);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 1e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 1e18);
        vm.expectRevert("Governance: initiative-already-registered");
        governance.registerInitiative(baseInitiative3);
    }

    /// Used to demonstrate how composite voting could allow using more power than intended
    function test_crit_accounting_mismatch() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (,, uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1_000e18);

        (uint256 voteLQTY1, uint256 voteOffset1,,,) = governance.initiativeStates(baseInitiative1);

        (uint256 voteLQTY2,,,,) = governance.initiativeStates(baseInitiative2);

        // Get power at time of vote
        uint256 votingPower = governance.lqtyToVotes(voteLQTY1, block.timestamp, voteOffset1);
        assertGt(votingPower, 0, "Non zero power");

        /// @audit TODO Fully digest and explain the bug
        // Warp to end so we check the threshold against future threshold

        {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());

            (
                IGovernance.VoteSnapshot memory snapshot,
                IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot1
            ) = governance.snapshotVotesForInitiative(baseInitiative1);
            (, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot2) =
                governance.snapshotVotesForInitiative(baseInitiative2);

            uint256 threshold = governance.getLatestVotingThreshold();
            assertLt(initiativeVoteSnapshot1.votes, threshold, "it didn't get rewards");

            uint256 votingPowerWithProjection = governance.lqtyToVotes(
                voteLQTY1, uint256(governance.epochStart() + governance.EPOCH_DURATION()), voteOffset1
            );
            assertLt(votingPower, threshold, "Current Power is not enough - Desynch A");
            assertLt(votingPowerWithProjection, threshold, "Future Power is also not enough - Desynch B");
        }
    }

    // Same setup as above (but no need for bug)
    // Show that you cannot withdraw
    function test_canAlwaysRemoveAllocation() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // Warp to end so we check the threshold against future threshold

        {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());

            (
                IGovernance.VoteSnapshot memory snapshot,
                IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot1
            ) = governance.snapshotVotesForInitiative(baseInitiative1);

            uint256 threshold = governance.getLatestVotingThreshold();
            assertLt(initiativeVoteSnapshot1.votes, threshold, "it didn't get rewards");
        }

        // Roll for
        vm.warp(block.timestamp + governance.UNREGISTRATION_AFTER_EPOCHS() * governance.EPOCH_DURATION());
        governance.unregisterInitiative(baseInitiative1);

        // @audit Warmup is not necessary
        // Warmup would only work for urgent veto
        // But urgent veto is not relevant here

        // I want to remove my allocation
        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2;
        governance.resetAllocations(removeInitiatives, true);

        int256[] memory removeDeltaLQTYVotes = new int256[](2);
        int256[] memory removeDeltaLQTYVetos = new int256[](2);
        removeDeltaLQTYVotes[0] = -1e18;

        vm.expectRevert("Cannot be negative");
        governance.allocateLQTY(initiativesToReset, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        address[] memory reAddInitiatives = new address[](1);
        reAddInitiatives[0] = baseInitiative1;
        int256[] memory reAddDeltaLQTYVotes = new int256[](1);
        reAddDeltaLQTYVotes[0] = 1e18;
        int256[] memory reAddDeltaLQTYVetos = new int256[](1);

        /// @audit This MUST revert, an initiative should not be re-votable once disabled
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(initiativesToReset, reAddInitiatives, reAddDeltaLQTYVotes, reAddDeltaLQTYVetos);
    }

    // Used to identify an accounting bug where vote power could be added to global state
    // While initiative is unregistered
    function test_allocationRemovalTotalLqtyMathIsSound() public {
        vm.startPrank(user2);
        address userProxy_2 = governance.deployUserProxy();

        lqty.approve(address(userProxy_2), 1_000e18);
        governance.depositLQTY(1_000e18);

        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.startPrank(user2);
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.startPrank(user);

        // Roll for the rest of the epochs so we can unregister
        vm.warp(block.timestamp + (governance.UNREGISTRATION_AFTER_EPOCHS()) * governance.EPOCH_DURATION());
        governance.unregisterInitiative(baseInitiative1);

        // Get state here
        // Get initiative state
        (uint256 b4_countedVoteLQTY, uint256 b4_countedVoteOffset) = governance.globalState();

        // I want to remove my allocation
        initiativesToReset = new address[](2);
        initiativesToReset[0] = baseInitiative1;
        initiativesToReset[1] = baseInitiative2;
        // don't need to explicitly remove allocation because it already gets reset
        address[] memory removeInitiatives = new address[](1);
        removeInitiatives[0] = baseInitiative2;
        int256[] memory removeDeltaLQTYVotes = new int256[](1);
        removeDeltaLQTYVotes[0] = 999e18;

        int256[] memory removeDeltaLQTYVetos = new int256[](1);

        governance.allocateLQTY(initiativesToReset, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        {
            // Get state here
            // TODO Get initiative state
            (uint256 after_countedVoteLQTY, uint256 after_countedVoteOffset) = governance.globalState();

            assertEq(after_countedVoteLQTY, b4_countedVoteLQTY, "LQTY should not change");
            assertEq(b4_countedVoteOffset, after_countedVoteOffset, "Offset should not change");
        }
    }

    // Remove allocation but check accounting
    // Need to find bug in accounting code
    function test_addRemoveAllocation_accounting() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // Warp to end so we check the threshold against future threshold
        {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());

            (
                IGovernance.VoteSnapshot memory snapshot,
                IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot1
            ) = governance.snapshotVotesForInitiative(baseInitiative1);

            uint256 threshold = governance.getLatestVotingThreshold();
            assertLt(initiativeVoteSnapshot1.votes, threshold, "it didn't get rewards");
        }

        // Roll for
        vm.warp(block.timestamp + governance.UNREGISTRATION_AFTER_EPOCHS() * governance.EPOCH_DURATION());

        /// === END SETUP === ///

        // Grab values b4 unregistering and b4 removing user allocation

        (uint256 b4_countedVoteLQTY, uint256 b4_countedVoteOffset) = governance.globalState();
        (,, uint256 b4_allocatedLQTY, uint256 b4_allocatedOffset) = governance.userStates(user);
        (uint256 b4_voteLQTY,,,,) = governance.initiativeStates(baseInitiative1);

        // Unregistering
        governance.unregisterInitiative(baseInitiative1);

        // We expect, the initiative to have the same values (because we track them for storage purposes)
        // TODO: Could change some of the values to make them 0 in view stuff
        // We expect the state to already have those removed
        // We expect the user to not have any changes

        (uint256 after_countedVoteLQTY,) = governance.globalState();

        assertEq(after_countedVoteLQTY, b4_countedVoteLQTY - b4_voteLQTY, "Global Lqty change after unregister");
        assertEq(1e18, b4_voteLQTY, "sanity check");

        (,, uint256 after_allocatedLQTY, uint256 after_unallocatedOffset) = governance.userStates(user);

        // We expect no changes here
        (
            uint256 after_voteLQTY,
            uint256 after_voteOffset,
            uint256 after_vetoLQTY,
            uint256 after_vetoOffset,
            uint256 after_lastEpochClaim
        ) = governance.initiativeStates(baseInitiative1);
        assertEq(b4_voteLQTY, after_voteLQTY, "Initiative votes are the same");

        // Need to test:
        // Total Votes
        // User Votes
        // Initiative Votes

        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2; // all user initiatives previously allocated to need to be included for resetting

        /// @audit the next call MUST not revert - this is a critical bug
        governance.resetAllocations(removeInitiatives, true);

        // After user counts LQTY the
        {
            (uint256 after_user_countedVoteLQTY, uint256 after_user_countedVoteOffset) = governance.globalState();
            // The LQTY was already removed
            assertEq(after_user_countedVoteLQTY, 0, "Removal 1");
        }

        // User State allocated LQTY changes by entire previous allocation amount
        {
            (,, uint256 after_user_allocatedLQTY,) = governance.userStates(user);
            assertEq(after_user_allocatedLQTY, 0, "Removal 2");
        }

        // Check user math only change is the LQTY amt
        // user was the only one allocated so since all alocations were reset, the initative lqty should be 0
        {
            (uint256 after_user_voteLQTY,,,,) = governance.initiativeStates(baseInitiative1);

            assertEq(after_user_voteLQTY, 0, "Removal 3");
        }
    }

    // Just pass a negative value and see what happens
    // forge test --match-test test_overflow_crit -vv
    function test_overflow_crit() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        (uint256 allocatedB4Test,,,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Test", allocatedB4Test);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2;

        (uint256 allocatedB4Removal,,,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Removal", allocatedB4Removal);

        governance.resetAllocations(removeInitiatives, true);
        (uint256 allocatedAfterRemoval,,,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfterRemoval", allocatedAfterRemoval);

        vm.expectRevert("Governance: nothing to reset");
        governance.resetAllocations(removeInitiatives, true);
        int256[] memory removeDeltaLQTYVotes = new int256[](2);
        int256[] memory removeDeltaLQTYVetos = new int256[](2);
        vm.expectRevert("Governance: voting nothing");
        governance.allocateLQTY(initiativesToReset, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);
        (uint256 allocatedAfter,,,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfter", allocatedAfter);
    }

    /// Find some random amount
    /// Divide into chunks
    /// Ensure chunks above 1 wei
    /// Go ahead and remove
    /// Ensure that at the end you remove 100%
    function test_fuzz_canRemoveExtact() public {}

    function test_allocateLQTY_revertsWhenInputArraysAreOfDifferentLengths() external {
        address[] memory initiativesToReset = new address[](0);
        address[][2] memory initiatives = [new address[](2), new address[](3)];
        int256[][2] memory votes = [new int256[](2), new int256[](3)];
        int256[][2] memory vetos = [new int256[](2), new int256[](3)];

        for (uint256 i = 0; i < 2; ++i) {
            for (uint256 j = 0; j < 2; ++j) {
                for (uint256 k = 0; k < 2; ++k) {
                    if (i == j && j == k) continue;

                    vm.expectRevert("Governance: array-length-mismatch");
                    governance.allocateLQTY(initiativesToReset, initiatives[i], votes[j], vetos[k]);
                }
            }
        }
    }

    function test_allocateLQTY_single() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);

        (,, uint256 allocatedLQTY, uint256 allocatedOffset) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint256 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        deltaLQTYVotes[0] = 1e18; //this should be 0
        int256[] memory deltaLQTYVetos = new int256[](1);

        // should revert if the initiative has been registered in the current epoch
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (,, allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1e18);

        (uint256 voteLQTY, uint256 voteOffset, uint256 vetoLQTY, uint256 vetoOffset,) =
            governance.initiativeStates(baseInitiative1);
        // should update the `voteLQTY` and `vetoLQTY` variables
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // TODO: assertions re: initiative vote & veto offsets
        // should remove or add the initiatives voting LQTY from the counter

        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        uint256 atEpoch;
        (voteLQTY,, vetoLQTY,, atEpoch) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        // should update the allocation mapping from user to initiative
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        // should snapshot the global and initiatives votes if there hasn't been a snapshot in the current epoch yet
        (, uint256 forEpoch) = governance.votesSnapshot();
        assertEq(forEpoch, governance.epoch() - 1);
        (, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.stopPrank();

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        IGovernance.UserState memory user2State;
        (user2State.unallocatedLQTY, user2State.unallocatedOffset, user2State.allocatedLQTY, user2State.allocatedOffset)
        = governance.userStates(user2);
        assertEq(user2State.allocatedLQTY, 0);
        assertEq(user2State.allocatedOffset, 0);
        assertEq(
            governance.lqtyToVotes(user2State.unallocatedLQTY, uint256(block.timestamp), user2State.unallocatedOffset),
            0
        );

        deltaLQTYVetos[0] = 1e18;

        vm.expectRevert("Governance: vote-and-veto");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVetos[0] = 0;

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // should update the user's allocated LQTY balance
        (,, allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, voteOffset, vetoLQTY, vetoOffset,) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        // TODO: assertions re: initiative vote + veto offsets

        // should revert if the user doesn't have enough unallocated LQTY available
        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        // user can only unallocate after voting cutoff
        initiatives[0] = baseInitiative1;
        governance.resetAllocations(initiatives, true);

        (,, allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 0);
        (countedVoteLQTY,) = governance.globalState();
        console.log("countedVoteLQTY: ", countedVoteLQTY);
        assertEq(countedVoteLQTY, 1e18);

        (voteLQTY, voteOffset, vetoLQTY, vetoOffset,) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // TODO: assertion re: vote offset
        assertEq(vetoOffset, 0);

        vm.stopPrank();
    }

    function test_allocateLQTY_after_cutoff() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);

        (,, uint256 allocatedLQTY, uint256 allocatedOffset) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint256 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        deltaLQTYVotes[0] = 1e18; //this should be 0
        int256[] memory deltaLQTYVetos = new int256[](1);

        // should revert if the initiative has been registered in the current epoch
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (,, allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1e18);

        (uint256 voteLQTY, uint256 voteOffset, uint256 vetoLQTY, uint256 vetoOffset,) =
            governance.initiativeStates(baseInitiative1);
        // should update the `voteLQTY` and `vetoLQTY` variables
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // should update the average staking timestamp for the initiative based on the average staking timestamp of the user's
        // voting and vetoing LQTY
        // TODO: assertions re: vote + veto offsets
        // should remove or add the initiatives voting LQTY from the counter

        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        uint256 atEpoch;
        (voteLQTY,, vetoLQTY,, atEpoch) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        // should update the allocation mapping from user to initiative
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        // should snapshot the global and initiatives votes if there hasn't been a snapshot in the current epoch yet
        (, uint256 forEpoch) = governance.votesSnapshot();
        assertEq(forEpoch, governance.epoch() - 1);
        (, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.stopPrank();

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        (, uint256 unallocatedOffset,,) = governance.userStates(user2);
        assertEq(governance.lqtyToVotes(1e18, block.timestamp, unallocatedOffset), 0);

        deltaLQTYVetos[0] = 1e18;

        vm.expectRevert("Governance: vote-and-veto");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVetos[0] = 0;

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // should update the user's allocated LQTY balance
        (,, allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, voteOffset, vetoLQTY, vetoOffset,) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        // TODO: offset vote + veto assertions

        // should revert if the user doesn't have enough unallocated LQTY available
        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = 1e18;
        // should only allow for unallocating votes or allocating vetos after the epoch voting cutoff
        // vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        (,, allocatedLQTY,) = governance.userStates(msg.sender);
        // this no longer reverts but the user allocation doesn't increase either way
        assertEq(allocatedLQTY, 0, "user can allocate after voting cutoff");

        vm.stopPrank();
    }

    function test_allocate_unregister() public {}

    function test_allocateLQTY_multiple() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 2e18);
        governance.depositLQTY(2e18);

        (,, uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint256 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 1e18;
        int256[] memory deltaLQTYVetos = new int256[](2);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (,, allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 2e18);
        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 2e18);

        (uint256 voteLQTY, uint256 voteOffset, uint256 vetoLQTY, uint256 vetoOffset,) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);

        (voteLQTY, voteOffset, vetoLQTY, vetoOffset,) = governance.initiativeStates(baseInitiative2);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
    }

    function test_allocateLQTY_fuzz_deltaLQTYVotes(uint256 _deltaLQTYVotes) public {
        _deltaLQTYVotes = bound(_deltaLQTYVotes, 1, 100e6 ether);

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        deal(address(lqty), user, _deltaLQTYVotes);
        lqty.approve(address(userProxy), _deltaLQTYVotes);
        governance.depositLQTY(_deltaLQTYVotes);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        deltaLQTYVotes[0] = int256(_deltaLQTYVotes);
        int256[] memory deltaLQTYVetos = new int256[](1);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function test_allocateLQTY_fuzz_deltaLQTYVetos(uint256 _deltaLQTYVetos) public {
        _deltaLQTYVetos = bound(_deltaLQTYVetos, 1, 100e6 ether);

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        deal(address(lqty), user, _deltaLQTYVetos);
        lqty.approve(address(userProxy), _deltaLQTYVetos);
        governance.depositLQTY(_deltaLQTYVetos);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        int256[] memory deltaLQTYVetos = new int256[](1);
        deltaLQTYVetos[0] = int256(_deltaLQTYVetos);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        /// @audit needs overflow tests!!
        vm.stopPrank();
    }

    function test_claimForInitiative() public {
        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        governance.depositLQTY(1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaVoteLQTY = new int256[](2);
        deltaVoteLQTY[0] = 500e18;
        deltaVoteLQTY[1] = 500e18;
        int256[] memory deltaVetoLQTY = new int256[](2);
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        (,, uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        // should compute the claim and transfer it to the initiative

        assertEq(governance.claimForInitiative(baseInitiative1), 5000e18, "first claim");
        // 2nd claim = 0
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(governance.claimForInitiative(baseInitiative2), 5000e18, "first claim 2");
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiativesToReset = new address[](2);
        initiativesToReset[0] = baseInitiative1;
        initiativesToReset[1] = baseInitiative2;
        initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        deltaVoteLQTY = new int256[](1);
        deltaVetoLQTY = new int256[](1);
        deltaVoteLQTY[0] = 495e18;
        // @audit user can't deallocate because votes already get reset
        // deltaVoteLQTY[1] = -495e18;
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(baseInitiative1), 10000e18);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 15000e18);

        (IGovernance.InitiativeStatus status,, uint256 claimable) = governance.getInitiativeState(baseInitiative2);
        console.log("res", uint8(status));
        console.log("claimable", claimable);
        (uint256 votes,,, uint256 vetos) = governance.votesForInitiativeSnapshot(baseInitiative2);
        console.log("snapshot votes", votes);
        console.log("snapshot vetos", vetos);

        console.log("governance.getLatestVotingThreshold()", governance.getLatestVotingThreshold());
        assertEq(governance.claimForInitiative(baseInitiative2), 0, "zero 2");
        assertEq(governance.claimForInitiative(baseInitiative2), 0, "zero 3");

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18, "zero bal");

        vm.stopPrank();
    }

    // this shouldn't happen
    function off_claimForInitiativeEOA() public {
        address EOAInitiative = address(0xbeef);

        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        governance.depositLQTY(1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = EOAInitiative; // attempt for an EOA
        initiatives[1] = baseInitiative2;
        int256[] memory deltaVoteLQTY = new int256[](2);
        deltaVoteLQTY[0] = 500e18;
        deltaVoteLQTY[1] = 500e18;
        int256[] memory deltaVetoLQTY = new int256[](2);
        governance.allocateLQTY(initiativesToReset, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        (,, uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        // should compute the claim and transfer it to the initiative
        assertEq(governance.claimForInitiative(EOAInitiative), 5000e18);
        governance.claimForInitiative(EOAInitiative);
        assertEq(governance.claimForInitiative(EOAInitiative), 0);
        assertEq(lusd.balanceOf(EOAInitiative), 5000e18);

        assertEq(governance.claimForInitiative(baseInitiative2), 5000e18);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiatives[0] = EOAInitiative;
        initiatives[1] = baseInitiative2;
        deltaVoteLQTY[0] = 495e18;
        deltaVoteLQTY[1] = -495e18;
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(EOAInitiative), 10000e18);
        // should not allow double claiming
        assertEq(governance.claimForInitiative(EOAInitiative), 0);

        assertEq(lusd.balanceOf(EOAInitiative), 15000e18);

        assertEq(governance.claimForInitiative(baseInitiative2), 0);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();
    }

    function test_multicall() public {
        vm.startPrank(user);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        uint256 lqtyAmount = 1000e18;
        uint256 lqtyBalance = lqty.balanceOf(user);

        lqty.approve(address(governance.deriveUserProxyAddress(user)), lqtyAmount);

        bytes[] memory data = new bytes[](8);
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaVoteLQTY = new int256[](1);
        deltaVoteLQTY[0] = int256(uint256(lqtyAmount));
        int256[] memory deltaVetoLQTY = new int256[](1);

        int256[] memory deltaVoteLQTY_ = new int256[](1);
        deltaVoteLQTY_[0] = 1;

        data[0] = abi.encodeWithSignature("deployUserProxy()");
        data[1] = abi.encodeWithSignature("depositLQTY(uint256)", lqtyAmount);
        data[2] = abi.encodeWithSignature(
            "allocateLQTY(address[],address[],int256[],int256[])",
            initiativesToReset,
            initiatives,
            deltaVoteLQTY,
            deltaVetoLQTY
        );
        data[3] = abi.encodeWithSignature("userStates(address)", user);
        data[4] = abi.encodeWithSignature("snapshotVotesForInitiative(address)", baseInitiative1);
        data[5] = abi.encodeWithSignature(
            "allocateLQTY(address[],address[],int256[],int256[])",
            initiatives,
            initiatives,
            deltaVoteLQTY_,
            deltaVetoLQTY
        );
        data[6] = abi.encodeWithSignature("resetAllocations(address[],bool)", initiatives, true);
        data[7] = abi.encodeWithSignature("withdrawLQTY(uint256)", lqtyAmount);
        bytes[] memory response = governance.multiDelegateCall(data);

        (,, uint256 allocatedLQTY,) = abi.decode(response[3], (uint256, uint256, uint256, uint256));
        assertEq(allocatedLQTY, lqtyAmount);
        (IGovernance.VoteSnapshot memory votes, IGovernance.InitiativeVoteSnapshot memory votesForInitiative) =
            abi.decode(response[4], (IGovernance.VoteSnapshot, IGovernance.InitiativeVoteSnapshot));
        assertEq(votes.votes + votesForInitiative.votes, 0);
        assertEq(lqty.balanceOf(user), lqtyBalance);

        vm.stopPrank();
    }

    /*
     * TODO
    function test_nonReentrant() public {
        MockInitiative mockInitiative = new MockInitiative(address(governance));

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, governance.epoch());
        governance.tester_setVotesSnapshot(snapshot);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 2e18);
        vm.stopPrank();

        vm.startPrank(user);
        lusd.approve(address(governance), 2e18);
        vm.stopPrank();

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.registerInitiative(address(mockInitiative));
        uint256 atEpoch = governance.registeredInitiatives(address(mockInitiative));
        assertEq(atEpoch, governance.epoch());

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(mockInitiative);
        int256[] memory deltaLQTYVotes = new int256[](1);
        int256[] memory deltaLQTYVetos = new int256[](1);
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        snapshot = IGovernance.VoteSnapshot(1, governance.epoch() - 1);
        governance.tester_setVotesSnapshot(snapshot);

        IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot =
            IGovernance.InitiativeVoteSnapshot(1, governance.epoch() - 1, governance.epoch() - 1, 0);
        governance.tester_setVotesForInitiativeSnapshot(address(mockInitiative), initiativeSnapshot);

        governance.claimForInitiative(address(mockInitiative));

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        initiativeSnapshot = IGovernance.InitiativeVoteSnapshot(0, governance.epoch() - 1, 0, 0);
        governance.tester_setVotesForInitiativeSnapshot(address(mockInitiative), initiativeSnapshot);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() * 4);

        governance.unregisterInitiative(address(mockInitiative));
    }
    */

    // CS exploit PoC
    function test_allocateLQTY_overflow() public {
        vm.startPrank(user);

        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;

        int256[] memory deltaLQTYVotes = new int256[](2);
        deltaLQTYVotes[0] = 1;
        deltaLQTYVotes[1] = type(int256).max;
        int256[] memory deltaLQTYVetos = new int256[](2);
        deltaLQTYVetos[0] = 0;
        deltaLQTYVetos[1] = 0;

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.expectRevert("Governance: insufficient-or-allocated-lqty");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVotes[0] = 0;
        deltaLQTYVotes[1] = 0;
        deltaLQTYVetos[0] = 1;
        deltaLQTYVetos[1] = type(int256).max;

        vm.expectRevert("Governance: insufficient-or-allocated-lqty");
        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function test_voting_power_increase() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        (,, uint256 allocatedLQTY0, uint256 allocatedOffset0) = governance.userStates(user);
        uint256 currentUserPower0 = governance.lqtyToVotes(allocatedLQTY0, block.timestamp, allocatedOffset0);

        (uint256 voteLQTY0, uint256 voteOffset0,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower0 = governance.lqtyToVotes(voteLQTY0, block.timestamp, voteOffset0);

        // (uint256 votes, uint256 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        // console2.log("votes0: ", votes);

        // =========== epoch 2 ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // check user voting power for the current epoch
        (,, uint256 allocatedLQTY1, uint256 allocatedOffset1) = governance.userStates(user);
        uint256 currentUserPower1 = governance.lqtyToVotes(allocatedLQTY1, block.timestamp, allocatedOffset1);
        // user's allocated lqty should have non-zero voting power
        assertGt(currentUserPower1, 0, "current user voting power is 0");

        // check initiative voting power for the current epoch
        (uint256 voteLQTY1, uint256 votOffset1,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower1 = governance.lqtyToVotes(voteLQTY1, block.timestamp, votOffset1);
        assertGt(currentInitiativePower1, 0, "current initiative voting power is 0");
        assertEq(currentUserPower1, currentInitiativePower1, "initiative and user voting power should be equal");

        // (uint256 votes, uint256 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        // =========== epoch 2 (end) ==================
        // 3. warp to end of epoch 2 to see increase in voting power
        // NOTE: voting power increases after any amount of time because the block.timestamp passed into vote power calculation changes
        vm.warp(block.timestamp + EPOCH_DURATION - 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // user voting power should increase over a given chunk of time
        (,, uint256 allocatedLQTY2, uint256 allocatedOffset2) = governance.userStates(user);
        uint256 currentUserPower2 = governance.lqtyToVotes(allocatedLQTY2, block.timestamp, allocatedOffset2);
        assertGt(currentUserPower2, currentUserPower1);

        // initiative voting power should increase over a given chunk of time
        (uint256 voteLQTY2, uint256 voteOffset2,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower2 = governance.lqtyToVotes(voteLQTY2, block.timestamp, voteOffset2);
        assertEq(
            currentUserPower2, currentInitiativePower2, "user power and initiative power should increase by same amount"
        );

        // votes should only get counted in the next epoch after they were allocated
        (uint256 votes, uint256 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, 0, "votes get counted in epoch that they were allocated");

        // =========== epoch 3 ==================
        // 4. warp to third epoch and check voting power
        vm.warp(block.timestamp + 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // user voting power should increase
        (,, uint256 allocatedLQTY3, uint256 allocatedOffset) = governance.userStates(user);
        uint256 currentUserPower3 = governance.lqtyToVotes(allocatedLQTY3, block.timestamp, allocatedOffset);

        // votes should match the voting power for the initiative and subsequently the user since they're the only one allocated
        (uint256 voteLQTY3, uint256 voteOffset3,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower3 = governance.lqtyToVotes(voteLQTY3, block.timestamp, voteOffset3);

        // votes should be counted in this epoch
        (votes, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, currentUserPower3, "initiative votes != user allocated lqty power");
        assertEq(votes, currentInitiativePower3, "initiative votes != iniative allocated lqty power");

        // TODO: check the increase in votes at the end of this epoch
        vm.warp(block.timestamp + EPOCH_DURATION - 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        (,, uint256 allocatedLQTY4, uint256 allocatedOffset4) = governance.userStates(user);
        uint256 currentUserPower4 = governance.lqtyToVotes(allocatedLQTY4, block.timestamp, allocatedOffset4);

        (uint256 voteLQTY4, uint256 voteOffset4,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower4 = governance.lqtyToVotes(voteLQTY4, block.timestamp, voteOffset4);

        // checking if snapshotting at the end of an epoch increases the voting power
        (uint256 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, votes2, "votes for an initiative snapshot increase in same epoch");

        // =========== epoch 3 (end) ==================
    }

    // increase in user voting power and initiative voting power should be equivalent
    function test_voting_power_in_same_epoch_as_allocation() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch
        assertEq(2, governance.epoch(), "not in epoch 2");

        // check user voting power before allocation at epoch start
        (,, uint256 allocatedLQTY0, uint256 allocatedOffset0) = governance.userStates(user);
        uint256 currentUserPower0 = governance.lqtyToVotes(allocatedLQTY0, block.timestamp, allocatedOffset0);
        assertEq(currentUserPower0, 0, "user has voting power > 0");

        // check initiative voting power before allocation at epoch start
        (uint256 voteLQTY0, uint256 voteOffset0,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower0 = governance.lqtyToVotes(voteLQTY0, block.timestamp, voteOffset0);
        assertEq(currentInitiativePower0, 0, "current initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        vm.warp(block.timestamp + (EPOCH_DURATION - 1)); // warp to end of second epoch
        assertEq(2, governance.epoch(), "not in epoch 2");

        // check user voting power after allocation at epoch end
        (,, uint256 allocatedLQTY1, uint256 allocatedOffset1) = governance.userStates(user);
        uint256 currentUserPower1 = governance.lqtyToVotes(allocatedLQTY1, block.timestamp, allocatedOffset1);
        assertGt(currentUserPower1, 0, "user has no voting power after allocation");

        // check initiative voting power after allocation at epoch end
        (uint256 voteLQTY1, uint256 voteOffset1,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower1 = governance.lqtyToVotes(voteLQTY1, block.timestamp, voteOffset1);
        assertGt(currentInitiativePower1, 0, "initiative has no voting power after allocation");

        // check that user and initiative voting power is equivalent at epoch end
        assertEq(currentUserPower1, currentInitiativePower1, "currentUserPower1 != currentInitiativePower1");

        vm.warp(block.timestamp + (EPOCH_DURATION * 40));
        assertEq(42, governance.epoch(), "not in epoch 42");

        // get user voting power after multiple epochs
        (,, uint256 allocatedLQTY2, uint256 allocatedOffset2) = governance.userStates(user);
        uint256 currentUserPower2 = governance.lqtyToVotes(allocatedLQTY2, block.timestamp, allocatedOffset2);
        assertGt(currentUserPower2, currentUserPower1, "user voting power doesn't increase");

        // get initiative voting power after multiple epochs
        (uint256 voteLQTY2, uint256 voteOffset2,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower2 = governance.lqtyToVotes(voteLQTY2, block.timestamp, voteOffset2);
        assertGt(currentInitiativePower2, currentInitiativePower1, "initiative voting power doesn't increase");

        // check that initiative and user voting always track each other
        assertEq(currentUserPower2, currentInitiativePower2, "voting powers don't match");
    }

    // initiative's increase in voting power after a snapshot is the same as the increase in power calculated using the initiative's allocation at the start and end of the epoch
    // |      deposit      |     allocate     |    snapshot     |
    // |====== epoch 1=====|==== epoch 2 =====|==== epoch 3 ====|
    function test_voting_power_increase_in_an_epoch() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // get initiative voting power at start of epoch
        (uint256 voteLQTY0, uint256 voteOffset0,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower0 = governance.lqtyToVotes(voteLQTY0, block.timestamp, voteOffset0);
        assertEq(currentInitiativePower0, 0, "initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get initiative voting power at time of snapshot
        (uint256 voteLQTY1, uint256 voteOffset1,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower1 = governance.lqtyToVotes(voteLQTY1, block.timestamp, voteOffset1);
        assertGt(currentInitiativePower1, 0, "initiative voting power is 0");

        uint256 deltaInitiativeVotingPower = currentInitiativePower1 - currentInitiativePower0;

        // 4. votes should be counted in this epoch
        (uint256 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, deltaInitiativeVotingPower, "voting power should increase by amount user allocated");
    }

    // checking that voting power calculated from lqtyAllocatedByUserToInitiative is equivalent to the voting power using values returned by userStates
    function test_voting_power_lqtyAllocatedByUserToInitiative() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // get user voting power at start of epoch from lqtyAllocatedByUserToInitiative
        (uint256 voteLQTY, uint256 voteOffset,,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        (,, uint256 allocatedLQTY, uint256 allocatedOffset) = governance.userStates(user);
        uint256 currentInitiativePowerFrom1 = governance.lqtyToVotes(voteLQTY, block.timestamp, voteOffset);
        uint256 currentInitiativePowerFrom2 = governance.lqtyToVotes(allocatedLQTY, block.timestamp, allocatedOffset);

        assertEq(
            currentInitiativePowerFrom1,
            currentInitiativePowerFrom2,
            "currentInitiativePowerFrom1 != currentInitiativePowerFrom2"
        );
    }

    // checking if allocating to a different initiative in a different epoch modifies the allocated offset
    function test_allocated_offset() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 2e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // user allocates to baseInitiative1
        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 2
        (,,, uint256 allocatedOffset1) = governance.userStates(user);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative2 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to third epoch

        address[] memory initiativesToReset = new address[](1);
        initiativesToReset[0] = address(baseInitiative1);
        // this should reset all alloc to initiative1, and divert it to initative 2
        _allocateLQTYToInitiative(user, baseInitiative2, 1e18, initiativesToReset);

        // check offsets are equal
        (,,, uint256 allocatedOffset2) = governance.userStates(user);
        assertEq(allocatedOffset1, allocatedOffset2);
    }

    // checking if allocating to same initiative modifies the average timestamp
    // forge test --match-test test_average_timestamp_same_initiative -vv
    function test_offset_same_initiative() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 2e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // user allocates to baseInitiative1
        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 2
        (,,, uint256 allocatedOffset1) = governance.userStates(user);
        console2.log("allocatedOffset1: ", allocatedOffset1);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative1 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION + 200); // warp to third epoch

        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 3
        (,,, uint256 allocatedOffset2) = governance.userStates(user);
        assertEq(allocatedOffset2, allocatedOffset1, "offsets differ");
    }

    // checking if allocating to same initiative modifies the average timestamp
    function test_offset_allocate_same_initiative_fuzz(uint256 allocateAmount) public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = uint256(allocateAmount % lqty.balanceOf(user));
        vm.assume(lqtyAmount > 0);
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // clamp lqtyAmount by half of what user staked
        uint256 lqtyAmount2 = uint256(bound(allocateAmount, 1, lqtyAmount));
        _allocateLQTY(user, lqtyAmount2);

        // get user voting power at start of epoch 2
        (, uint256 unallocatedOffset1,, uint256 allocatedOffset1) = governance.userStates(user);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative1 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to third epoch

        // clamp lqtyAmount by amount user staked
        vm.assume(lqtyAmount > lqtyAmount2);
        vm.assume(lqtyAmount - lqtyAmount2 > 1);
        uint256 lqtyAmount3 = uint256(bound(allocateAmount, 1, lqtyAmount - lqtyAmount2));
        _allocateLQTY(user, lqtyAmount3);

        // get user voting power at start of epoch 3 from lqtyAllocatedByUserToInitiative
        (, uint256 unallocatedOffset2,, uint256 allocatedOffset2) = governance.userStates(user);
        assertEq(unallocatedOffset2 + allocatedOffset2, unallocatedOffset1 + allocatedOffset1, "offset2 != offset1");
    }

    function test_voting_snapshot_start_vs_end_epoch() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // get initiative voting power at start of epoch
        (uint256 voteLQTY0, uint256 voteOffset0,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower0 = governance.lqtyToVotes(voteLQTY0, block.timestamp, voteOffset0);
        assertEq(currentInitiativePower0, 0, "initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        uint256 stateBeforeSnapshottingVotes = vm.snapshotState();

        // =========== epoch 3 (start) ==================
        // 3a. warp to start of third epoch
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in 3rd epoch");
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get initiative voting power at start of epoch
        (uint256 voteLQTY1, uint256 voteOffset1,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower1 = governance.lqtyToVotes(voteLQTY1, block.timestamp, voteOffset1);

        // 4a. votes from snapshotting at begging of epoch
        (uint256 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        console2.log("currentInitiativePower1: ", currentInitiativePower1);
        console2.log("votes: ", votes);

        // =========== epoch 3 (end) ==================
        // revert EVM to state before snapshotting
        vm.revertToState(stateBeforeSnapshottingVotes);

        // 3b. warp to end of third epoch
        vm.warp(block.timestamp + (EPOCH_DURATION * 2) - 1);
        assertEq(3, governance.epoch(), "not in 3rd epoch");
        governance.snapshotVotesForInitiative(baseInitiative1);

        // 4b. votes from snapshotting at end of epoch
        (uint256 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, votes2, "votes from snapshot are dependent on time at snapshot");
    }

    // checks that there's no difference to resulting voting power from allocating at start or end of epoch
    function test_voting_power_no_difference_in_allocating_start_or_end_of_epoch() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        uint256 stateBeforeAllocation = vm.snapshotState();

        // =========== epoch 2 (start) ==================
        // 2a. user allocates at start of epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3a. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get voting power from allocation in previous epoch
        (uint256 votesFromAllocatingAtEpochStart,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        // ========================================
        // ===== revert to initial state ==========
        // ========================================

        // ===============  epoch 1 ===============
        // revert EVM to state before allocation
        vm.revertToState(stateBeforeAllocation);

        // ===============  epoch 2 (end - just before cutoff) ===============
        // 2b. user allocates at end of epoch 2
        vm.warp(block.timestamp + (EPOCH_DURATION * 2) - governance.EPOCH_VOTING_CUTOFF()); // warp to end of second epoch before the voting cutoff

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3b. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get voting power from allocation in previous epoch
        (uint256 votesFromAllocatingAtEpochEnd,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(
            votesFromAllocatingAtEpochStart,
            votesFromAllocatingAtEpochEnd,
            "allocating is more favorable at certain point in epoch"
        );
    }

    // deallocating is correctly reflected in voting power for next epoch
    function test_voting_power_decreases_next_epoch() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        console2.log("current epoch A: ", governance.epoch());
        governance.snapshotVotesForInitiative(baseInitiative1);

        // 4. votes should be counted in this epoch
        (uint256 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertGt(votes, 0, "voting power should increase");

        _deAllocateLQTY(user, 0);

        governance.snapshotVotesForInitiative(baseInitiative1);

        // 5. votes should still be counted in this epoch
        (uint256 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertGt(votes2, 0, "voting power should not decrease this epoch");

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        console2.log("current epoch B: ", governance.epoch());
        governance.snapshotVotesForInitiative(baseInitiative1);

        // 6. votes should be decreased in this epoch
        (uint256 votes3,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes3, 0, "voting power should be decreased in this epoch");
    }

    function test_deallocating_decreases_offset() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        (,,, uint256 allocatedOffset) = governance.userStates(user);
        assertGt(allocatedOffset, 0);

        _deAllocateLQTY(user, 0);

        (,,, allocatedOffset) = governance.userStates(user);
        assertEq(allocatedOffset, 0);
    }

    // vetoing shouldn't affect voting power of the initiative
    function test_vote_and_veto() public {
        // =========== epoch 1 ==================
        governance = new GovernanceTester(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: uint256(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint256 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // 1. user2 stakes lqty
        _stakeLQTY(user2, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2a. user allocates votes in epoch 2 for initiative
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // 2b. user2 allocates vetos for initiative
        _veto(user2, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        console2.log("current epoch A: ", governance.epoch());
        governance.snapshotVotesForInitiative(baseInitiative1);

        // voting power for initiative should be the same as votes from snapshot
        (uint256 voteLQTY, uint256 voteOffset,,,) = governance.initiativeStates(baseInitiative1);
        uint256 currentInitiativePower = governance.lqtyToVotes(voteLQTY, block.timestamp, voteOffset);

        // 4. votes should not affect accounting for votes
        (uint256 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, currentInitiativePower, "voting power of initiative should not be affected by vetos");
    }

    struct StakingOp {
        uint256 lqtyAmount;
        uint256 waitTime;
    }

    function test_NoDustInUnallocatedOffsetAfterAllocatingAllLQTY(uint256[3] memory _votes, StakingOp[4] memory _stakes)
        external
    {
        address[] memory initiatives = new address[](_votes.length + 1);

        // Ensure initiatives can be registered
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);

        // Register as many initiatives as needed
        vm.startPrank(lusdHolder);
        for (uint256 i = 0; i < initiatives.length; ++i) {
            initiatives[i] = makeAddr(string.concat("initiative", i.toString()));
            lusd.approve(address(governance), REGISTRATION_FEE);
            governance.registerInitiative(initiatives[i]);
        }
        vm.stopPrank();

        // Ensure the new initiatives are votable
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.startPrank(user);
        {
            // Don't wait too long or initiatives might time out
            uint256 maxWaitTime = EPOCH_DURATION * UNREGISTRATION_AFTER_EPOCHS / _stakes.length;
            address userProxy = governance.deriveUserProxyAddress(user);
            uint256 lqtyBalance = lqty.balanceOf(user);
            uint256 unallocatedLQTY_ = 0;

            for (uint256 i = 0; i < _stakes.length; ++i) {
                _stakes[i].lqtyAmount = _bound(_stakes[i].lqtyAmount, 1, lqtyBalance - (_stakes.length - 1 - i));
                lqtyBalance -= _stakes[i].lqtyAmount;
                unallocatedLQTY_ += _stakes[i].lqtyAmount;

                lqty.approve(userProxy, _stakes[i].lqtyAmount);
                governance.depositLQTY(_stakes[i].lqtyAmount);

                _stakes[i].waitTime = _bound(_stakes[i].waitTime, 1, maxWaitTime);
                vm.warp(block.timestamp + _stakes[i].waitTime);
            }

            address[] memory initiativesToReset; // left empty
            int256[] memory votes = new int256[](initiatives.length);
            int256[] memory vetos = new int256[](initiatives.length); // left zero

            for (uint256 i = 0; i < initiatives.length - 1; ++i) {
                uint256 vote = _bound(_votes[i], 1, unallocatedLQTY_ - (initiatives.length - 1 - i));
                unallocatedLQTY_ -= vote;
                votes[i] = int256(vote);
            }

            // Cast all remaining LQTY on the last initiative
            votes[initiatives.length - 1] = int256(unallocatedLQTY_);

            vm.assume(governance.secondsWithinEpoch() < EPOCH_VOTING_CUTOFF);
            governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
        }
        vm.stopPrank();

        (uint256 unallocatedLQTY, uint256 unallocatedOffset,,) = governance.userStates(user);
        assertEqDecimal(unallocatedLQTY, 0, 18, "user should have no unallocated LQTY");
        assertEqDecimal(unallocatedOffset, 0, 18, "user should have no unallocated offset");
    }

    function test_WhenAllocatingTinyAmounts_VotingPowerDoesNotTurnNegativeDueToRoundingError(
        uint256 initialVotingPower,
        uint256 numInitiatives
    ) external {
        initialVotingPower = bound(initialVotingPower, 1, 20);
        numInitiatives = bound(numInitiatives, 1, 20);

        address[] memory initiatives = new address[](numInitiatives);

        // Ensure initiatives can be registered
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);

        // Register as many initiatives as needed
        vm.startPrank(lusdHolder);
        for (uint256 i = 0; i < initiatives.length; ++i) {
            initiatives[i] = makeAddr(string.concat("initiative", i.toString()));
            lusd.approve(address(governance), REGISTRATION_FEE);
            governance.registerInitiative(initiatives[i]);
        }
        vm.stopPrank();

        // Ensure the new initiatives are votable
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.startPrank(user);
        {
            address userProxy = governance.deriveUserProxyAddress(user);
            lqty.approve(userProxy, type(uint256).max);
            governance.depositLQTY(1);

            // By waiting `initialVotingPower` seconds while having 1 wei LQTY staked,
            // we accrue exactly `initialVotingPower`
            vm.warp(block.timestamp + initialVotingPower);

            governance.depositLQTY(1 ether);

            address[] memory initiativesToReset; // left empty
            int256[] memory votes = new int256[](initiatives.length);
            int256[] memory vetos = new int256[](initiatives.length); // left zero

            for (uint256 i = 0; i < initiatives.length; ++i) {
                votes[i] = 1;
            }

            governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
        }
        vm.stopPrank();

        (uint256 unallocatedLQTY, uint256 unallocatedOffset,,) = governance.userStates(user);
        int256 votingPower = int256(unallocatedLQTY * block.timestamp) - int256(unallocatedOffset);

        // Even though we are allocating tiny amounts, each allocation
        // reduces voting power by 1 (due to rounding), but not below zero
        assertEq(
            votingPower,
            int256(initialVotingPower > numInitiatives ? initialVotingPower - numInitiatives : 0),
            "voting power should stay non-negative"
        );
    }

    // We find that a user's unallocated voting power can't be turned negative through manipulation, which is
    // demonstrated in the next test.
    //
    // Whenever a user withdraws LQTY, they can lose more voting power than they should, due to rounding error in the
    // calculation of their remaining offset:
    //
    //   unallocatedOffset -= FLOOR(lqtyDecrease * unallocatedOffset / unallocatedLQTY)
    //   unallocatedLQTY -= lqtyDecrease
    //
    // For reference, unallocated voting power at time `t` is calculated as:
    //
    //   unallocatedLQTY * t - unallocatedOffset
    //
    // The decrement of `unallocatedOffset` is rounded down, consequently `unallocatedOffset` is rounded up, in turn the
    // voting power is rounded down. So when time a user has some relatively small positive unallocated voting power and
    // a significant amount of unallocated LQTY, and withdraws a tiny amount of LQTY (corresponding to less than a unit
    // of voting power), they lose a full unit of voting power.
    //
    // One might think that this can be done repeatedly in an attempt to manipulate unallocated voting power into
    // negative range, thus being able to allocate negative voting power to an initiative (if done very close to the
    // end of the present epoch), which would be bad as it would result in insolvency in initiatives that distribute
    // rewards in proportion to voting power allocated by voters (such as `BribeInitiative`).
    //
    // However, we find that this manipulation stops being effective once unallocated voting power reaches zero. Having
    // zero unallocated voting power means:
    //
    //   unallocatedLQTY * t - unallocatedOffset = 0
    //   unallocatedLQTY * t = unallocatedOffset
    //
    // Thus when unallocated voting power is zero, `unallocatedOffset` is a multiple of `unallocatedLQTY`, so there can
    // be no more rounding error when re-calculating `unallocatedOffset` on withdrawals.

    function test_WhenWithdrawingTinyAmounts_VotingPowerDoesNotTurnNegativeDueToRoundingError(
        uint256 initialVotingPower,
        uint256 numWithdrawals
    ) external {
        initialVotingPower = bound(initialVotingPower, 1, 20);
        numWithdrawals = bound(numWithdrawals, 1, 20);

        vm.startPrank(user);
        {
            address userProxy = governance.deriveUserProxyAddress(user);
            lqty.approve(userProxy, type(uint256).max);
            governance.depositLQTY(1);

            // By waiting `initialVotingPower` seconds while having 1 wei LQTY staked,
            // we accrue exactly `initialVotingPower`
            vm.warp(block.timestamp + initialVotingPower);

            governance.depositLQTY(1 ether);

            for (uint256 i = 0; i < numWithdrawals; ++i) {
                governance.withdrawLQTY(1);
            }
        }
        vm.stopPrank();

        (uint256 unallocatedLQTY, uint256 unallocatedOffset,,) = governance.userStates(user);
        int256 votingPower = int256(unallocatedLQTY * block.timestamp) - int256(unallocatedOffset);

        // Even though we are withdrawing tiny amounts, each withdrawal
        // reduces voting power by 1 (due to rounding), but not below zero
        assertEq(
            votingPower,
            int256(initialVotingPower > numWithdrawals ? initialVotingPower - numWithdrawals : 0),
            "voting power should stay non-negative"
        );
    }

    function test_Vote_Stake_Unvote() external {
        address[] memory noInitiatives;
        address[] memory initiatives = new address[](1);
        int256[] memory noVotes;
        int256[] memory votes = new int256[](1);
        int256[] memory vetos = new int256[](1);
        initiatives[0] = baseInitiative1;

        // Ensure the initial initiatives are active
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Have another user vote some on the initiative
        vm.startPrank(user2);
        {
            address userProxy = governance.deriveUserProxyAddress(user2);
            lqty.approve(userProxy, type(uint256).max);

            governance.depositLQTY(1 ether);
            votes[0] = 1 ether;
            governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);
        }
        vm.stopPrank();

        (uint256 voteLQTYBefore, uint256 voteOffsetBefore,,,) = governance.initiativeStates(baseInitiative1);

        vm.startPrank(user);
        {
            address userProxy = governance.deriveUserProxyAddress(user);
            lqty.approve(userProxy, type(uint256).max);

            // Vote 1 LQTY
            governance.depositLQTY(1 ether);
            votes[0] = 1 ether;
            governance.allocateLQTY(noInitiatives, initiatives, votes, vetos);

            vm.warp(block.timestamp + 1 days);

            // Increase stake then unvote 1 LQTY
            governance.depositLQTY(1 ether);
            governance.allocateLQTY(initiatives, noInitiatives, noVotes, noVotes);
        }
        vm.stopPrank();

        (uint256 voteLQTYAfter, uint256 voteOffsetAfter,,,) = governance.initiativeStates(baseInitiative1);
        assertEqDecimal(voteLQTYAfter, voteLQTYBefore, 18, "voteLQTYAfter != voteLQTYBefore");
        assertEqDecimal(voteOffsetAfter, voteOffsetBefore, 18, "voteOffsetAfter != voteOffsetBefore");
    }

    function _stakeLQTY(address staker, uint256 amount) internal {
        vm.startPrank(staker);
        address userProxy = governance.deriveUserProxyAddress(staker);
        lqty.approve(address(userProxy), amount);

        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocateLQTY(address allocator, uint256 amount) internal {
        vm.startPrank(allocator);

        address[] memory initiativesToReset;
        (uint256 currentVote,, uint256 currentVeto,,) =
            governance.lqtyAllocatedByUserToInitiative(allocator, address(baseInitiative1));
        if (currentVote != 0 || currentVeto != 0) {
            initiativesToReset = new address[](1);
            initiativesToReset[0] = address(baseInitiative1);
        }

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        deltaLQTYVotes[0] = int256(amount);
        int256[] memory deltaLQTYVetos = new int256[](1);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _allocateLQTYToInitiative(
        address allocator,
        address initiative,
        uint256 amount,
        address[] memory initiativesToReset
    ) internal {
        vm.startPrank(allocator);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory deltaLQTYVotes = new int256[](1);
        deltaLQTYVotes[0] = int256(amount);
        int256[] memory deltaLQTYVetos = new int256[](1);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _veto(address allocator, uint256 amount) internal {
        vm.startPrank(allocator);

        address[] memory initiativesToReset;
        (uint256 currentVote,, uint256 currentVeto,,) =
            governance.lqtyAllocatedByUserToInitiative(allocator, address(baseInitiative1));
        if (currentVote != 0 || currentVeto != 0) {
            initiativesToReset = new address[](1);
            initiativesToReset[0] = address(baseInitiative1);
        }

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaLQTYVotes = new int256[](1);
        int256[] memory deltaLQTYVetos = new int256[](1);
        deltaLQTYVetos[0] = int256(amount);

        governance.allocateLQTY(initiativesToReset, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _deAllocateLQTY(address allocator, uint256 amount) internal {
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;

        vm.startPrank(allocator);
        governance.resetAllocations(initiatives, true);
        vm.stopPrank();
    }
}

contract MockedGovernanceTest is GovernanceTest, MockStakingV1Deployer {
    function setUp() public override {
        (MockStakingV1 mockStakingV1, MockERC20Tester mockLQTY, MockERC20Tester mockLUSD) = deployMockStakingV1();

        mockLQTY.mint(user, 10_000e18);
        mockLQTY.mint(user2, 1_000e18);
        mockLUSD.mint(lusdHolder, 20_000e18);

        lqty = mockLQTY;
        lusd = mockLUSD;
        stakingV1 = mockStakingV1;

        super.setUp();
    }

    function _expectInsufficientAllowance() internal override {
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
    }

    function _expectInsufficientBalance() internal override {
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
    }

    function _expectInsufficientAllowanceAndBalance() internal override {
        _expectInsufficientAllowance();
    }
}

contract ForkedGovernanceTest is GovernanceTest {
    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20430000);

        lqty = ILQTY(MAINNET_LQTY);
        lusd = ILUSD(MAINNET_LUSD);
        stakingV1 = ILQTYStaking(MAINNET_LQTY_STAKING);

        super.setUp();
    }

    function _expectInsufficientAllowance() internal override {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
    }

    function _expectInsufficientBalance() internal override {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
    }

    function _expectInsufficientAllowanceAndBalance() internal override {
        _expectInsufficientBalance();
    }
}
