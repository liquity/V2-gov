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

contract GovernanceInternal is Governance {
    constructor(
        address _lqty,
        address _lusd,
        address _stakingV1,
        address _bold,
        Configuration memory _config,
        address[] memory _initiatives
    ) Governance(_lqty, _lusd, _stakingV1, _bold, _config, msg.sender, _initiatives) {}

    function averageAge(uint32 _currentTimestamp, uint32 _averageTimestamp) external pure returns (uint32) {
        return _averageAge(_currentTimestamp, _averageTimestamp);
    }

    function calculateAverageTimestamp(
        uint32 _prevOuterAverageTimestamp,
        uint32 _newInnerAverageTimestamp,
        uint88 _prevLQTYBalance,
        uint88 _newLQTYBalance
    ) external view returns (uint32) {
        return _calculateAverageTimestamp(
            _prevOuterAverageTimestamp, _newInnerAverageTimestamp, _prevLQTYBalance, _newLQTYBalance
        );
    }
}

contract GovernanceTest is Test {
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
    GovernanceInternal private governanceInternal;
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        governanceInternal = new GovernanceInternal(
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
    }

    // should not revert under any input
    function test_averageAge(uint32 _currentTimestamp, uint32 _timestamp) public {
        uint32 averageAge = governanceInternal.averageAge(_currentTimestamp, _timestamp);
        if (_timestamp == 0 || _currentTimestamp < _timestamp) {
            assertEq(averageAge, 0);
        } else {
            assertEq(averageAge, _currentTimestamp - _timestamp);
        }
    }

    // should not revert under any input
    function test_calculateAverageTimestamp(
        uint32 _prevOuterAverageTimestamp,
        uint32 _newInnerAverageTimestamp,
        uint88 _prevLQTYBalance,
        uint88 _newLQTYBalance
    ) public {
        uint32 highestTimestamp = (_prevOuterAverageTimestamp > _newInnerAverageTimestamp)
            ? _prevOuterAverageTimestamp
            : _newInnerAverageTimestamp;
        if (highestTimestamp > block.timestamp) vm.warp(highestTimestamp);
        governanceInternal.calculateAverageTimestamp(
            _prevOuterAverageTimestamp, _newInnerAverageTimestamp, _prevLQTYBalance, _newLQTYBalance
        );
    }

    function test_depositLQTY_withdrawLQTY() public {
        uint256 timeIncrease = 86400 * 30;
        vm.warp(block.timestamp + timeIncrease);

        vm.startPrank(user);

        // should revert with a 0 amount
        vm.expectRevert("Governance: zero-lqty-amount");
        governance.depositLQTY(0);

        // should revert if the `_lqtyAmount` > `lqty.allowance(msg.sender, userProxy)`
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        governance.depositLQTY(1e18);

        // should revert if the `_lqtyAmount` > `lqty.balanceOf(msg.sender)`
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.depositLQTY(type(uint88).max);

        // should not revert if the user doesn't have a UserProxy deployed yet
        address userProxy = governance.deriveUserProxyAddress(user);
        lqty.approve(address(userProxy), 1e18);
        // vm.expectEmit("DepositLQTY", abi.encode(user, 1e18));
        // deploy and deposit 1 LQTY
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        // first deposit should have an averageStakingTimestamp if block.timestamp
        assertEq(averageStakingTimestamp, block.timestamp);

        vm.warp(block.timestamp + timeIncrease);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 2e18);
        (allocatedLQTY, averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        // subsequent deposits should have a stake weighted average
        assertEq(averageStakingTimestamp, block.timestamp - timeIncrease / 2);

        // withdraw 0.5 half of LQTY
        vm.warp(block.timestamp + timeIncrease);

        vm.startPrank(address(this));
        vm.expectRevert("Governance: user-proxy-not-deployed");
        governance.withdrawLQTY(1e18);
        vm.stopPrank();

        vm.startPrank(user);

        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(type(uint88).max);

        governance.withdrawLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (allocatedLQTY, averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        assertEq(averageStakingTimestamp, (block.timestamp - timeIncrease) - timeIncrease / 2);

        // withdraw remaining LQTY
        governance.withdrawLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 0);
        (allocatedLQTY, averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        assertEq(averageStakingTimestamp, (block.timestamp - timeIncrease) - timeIncrease / 2);

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

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        governance.depositLQTYViaPermit(1e18, permitParams);

        permitParams.s = s;

        vm.startPrank(address(this));
        vm.expectRevert("UserProxy: owner-not-sender");
        governance.depositLQTYViaPermit(1e18, permitParams);
        vm.stopPrank();

        vm.startPrank(wallet.addr);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.depositLQTYViaPermit(type(uint88).max, permitParams);

        // deploy and deposit 1 LQTY
        governance.depositLQTYViaPermit(1e18, permitParams);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp) = governance.userStates(wallet.addr);
        assertEq(allocatedLQTY, 0);
        assertEq(averageStakingTimestamp, block.timestamp);
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
        vm.warp(_timestamp);
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
        vm.warp(_timestamp);
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
        vm.warp(_timestamp);
        governance.secondsWithinEpoch();
    }

    // should not revert under any input
    function test_lqtyToVotes(uint88 _lqtyAmount, uint256 _currentTimestamp, uint32 _averageTimestamp) public {
        governance.lqtyToVotes(_lqtyAmount, _currentTimestamp, _averageTimestamp);
    }

    function test_getLatestVotingThreshold() public {
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // is 0 when the previous epochs votes are 0
        assertEq(governance.getLatestVotingThreshold(), 0);

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (uint240 votes, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, 1);

        uint256 boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(1)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.getLatestVotingThreshold(), MIN_CLAIM / 1000);

        // check that votingThreshold is 4% of votes of previous epoch
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: 10e18,
                minAccrual: 10e18,
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        snapshot = IGovernance.VoteSnapshot(10000e18, 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (votes, forEpoch) = governance.votesSnapshot();
        assertEq(votes, 10000e18);
        assertEq(forEpoch, 1);

        boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(1)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.getLatestVotingThreshold(), 10000e18 * 0.04);
    }

    // should not revert under any state
    function test_calculateVotingThreshold_fuzz(
        uint128 _votes,
        uint16 _forEpoch,
        uint88 _boldAccrued,
        uint128 _votingThresholdFactor,
        uint88 _minClaim
    ) public {
        _votingThresholdFactor = _votingThresholdFactor % 1e18;
        /// Clamp to prevent misconfig
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                registrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                registrationWarmUpPeriod: REGISTRATION_WARM_UP_PERIOD,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: _votingThresholdFactor,
                minClaim: _minClaim,
                minAccrual: type(uint88).max,
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(_votes, _forEpoch);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (uint240 votes, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(votes, _votes);
        assertEq(forEpoch, _forEpoch);

        vm.store(address(governance), bytes32(uint256(1)), bytes32(abi.encode(_boldAccrued)));
        assertEq(governance.boldAccrued(), _boldAccrued);

        governance.getLatestVotingThreshold();
    }

    function test_registerInitiative() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (uint240 votes,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        // should revert if the `REGISTRATION_FEE` > `lqty.balanceOf(msg.sender)`
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.registerInitiative(baseInitiative3);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 2e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 2e18);

        // should revert if the registrant doesn't have enough voting power
        vm.expectRevert("Governance: insufficient-lqty");
        governance.registerInitiative(baseInitiative3);

        // should revert if the `REGISTRATION_FEE` > `lqty.allowance(msg.sender, governance)`
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        governance.depositLQTY(1e18);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        // should revert if `_initiative` is zero
        vm.expectRevert("Governance: zero-address");
        governance.registerInitiative(address(0));

        governance.registerInitiative(baseInitiative3);
        uint16 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        // should revert if the initiative was already registered
        vm.expectRevert("Governance: initiative-already-registered");
        governance.registerInitiative(baseInitiative3);

        vm.stopPrank();
    }

    // TODO: Broken: Fix it by simplifying most likely
    // forge test --match-test test_unregisterInitiative -vv
    function test_unregisterInitiative() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (uint240 votes, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, 1);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 1e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 1e18);
        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        // should revert if the initiative isn't registered
        vm.expectRevert("Governance: initiative-not-registered");
        governance.unregisterInitiative(baseInitiative3);

        governance.registerInitiative(baseInitiative3);
        uint16 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        // should revert if the initiative is still in the registration warm up period
        vm.expectRevert("Governance: initiative-in-warm-up");
        /// @audit should fail due to not waiting enough time
        governance.unregisterInitiative(baseInitiative3);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        // should revert if the initiative is still active or the vetos don't meet the threshold
        /// @audit TO REVIEW, this never got any votes, so it seems correct to remove
        // No votes = can be kicked
        vm.expectRevert("Governance: cannot-unregister-initiative");
        governance.unregisterInitiative(baseInitiative3);

        snapshot = IGovernance.VoteSnapshot(1e18, governance.epoch() - 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (votes, forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() * 3); // 3 more epochs

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

    // Test: You can always remove allocation
    // forge test --match-test test_crit_accounting_mismatch -vv
    function test_crit_accounting_mismatch() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int88[] memory deltaLQTYVetos = new int88[](2);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1_000e18);

        (uint88 voteLQTY1,, uint32 averageStakingTimestampVoteLQTY1,,) = governance.initiativeStates(baseInitiative1);

        (uint88 voteLQTY2,,,,) = governance.initiativeStates(baseInitiative2);

        // Get power at time of vote
        uint256 votingPower = governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);
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
                voteLQTY1, governance.epochStart() + governance.EPOCH_DURATION(), averageStakingTimestampVoteLQTY1
            );
            assertLt(votingPower, threshold, "Current Power is not enough - Desynch A");
            assertLt(votingPowerWithProjection, threshold, "Future Power is also not enough - Desynch B");
        }
    }

    // Same setup as above (but no need for bug)
    // Show that you cannot withdraw
    // forge test --match-test test_canAlwaysRemoveAllocation -vv
    function test_canAlwaysRemoveAllocation() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int88[] memory deltaLQTYVetos = new int88[](2);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

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
        // TODO: Check and prob separate

        // CRIT - I want to remove my allocation
        // I cannot
        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2;
        int88[] memory removeDeltaLQTYVotes = new int88[](2);
        // don't need to explicitly remove allocation because it already gets reset
        removeDeltaLQTYVotes[0] = 0;
        int88[] memory removeDeltaLQTYVetos = new int88[](2);

        governance.allocateLQTY(removeInitiatives, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        // Security Check | TODO: MORE INVARIANTS
        // trying to explicitly remove allocation fails because allocation gets reset
        removeDeltaLQTYVotes[0] = -1e18;

        vm.expectRevert(); // TODO: This is a panic
        governance.allocateLQTY(removeInitiatives, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        address[] memory reAddInitiatives = new address[](1);
        reAddInitiatives[0] = baseInitiative1;
        int88[] memory reAddDeltaLQTYVotes = new int88[](1);
        reAddDeltaLQTYVotes[0] = 1e18;
        int88[] memory reAddDeltaLQTYVetos = new int88[](1);

        /// @audit This MUST revert, an initiative should not be re-votable once disabled
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(reAddInitiatives, reAddInitiatives, reAddDeltaLQTYVotes, reAddDeltaLQTYVetos);
    }

    // Remove allocation but check accounting
    // Need to find bug in accounting code
    // forge test --match-test test_addRemoveAllocation_accounting -vv
    function test_addRemoveAllocation_accounting() public {
        // User setup
        vm.startPrank(user);
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1_000e18);
        governance.depositLQTY(1_000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        /// Setup and vote for 2 initiatives, 0.1% vs 99.9%
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int88[] memory deltaLQTYVetos = new int88[](2);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

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

        (uint88 b4_countedVoteLQTY, uint32 b4_countedVoteLQTYAverageTimestamp) = governance.globalState();
        (uint88 b4_allocatedLQTY, uint32 b4_averageStakingTimestamp) = governance.userStates(user);
        (uint88 b4_voteLQTY,,,,) = governance.initiativeStates(baseInitiative1);

        // Unregistering
        governance.unregisterInitiative(baseInitiative1);

        // We expect, the initiative to have the same values (because we track them for storage purposes)
        // TODO: Could change some of the values to make them 0 in view stuff
        // We expect the state to already have those removed
        // We expect the user to not have any changes

        (uint88 after_countedVoteLQTY,) = governance.globalState();

        assertEq(after_countedVoteLQTY, b4_countedVoteLQTY - b4_voteLQTY, "Global Lqty change after unregister");
        assertEq(1e18, b4_voteLQTY, "sanity check");

        (uint88 after_allocatedLQTY, uint32 after_averageStakingTimestamp) = governance.userStates(user);

        // We expect no changes here
        (
            uint88 after_voteLQTY,
            uint88 after_vetoLQTY,
            uint32 after_averageStakingTimestampVoteLQTY,
            uint32 after_averageStakingTimestampVetoLQTY,
            uint16 after_lastEpochClaim
        ) = governance.initiativeStates(baseInitiative1);
        assertEq(b4_voteLQTY, after_voteLQTY, "Initiative votes are the same");

        // Need to test:
        // Total Votes
        // User Votes
        // Initiative Votes

        // I cannot
        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2; // all user initiatives previously allocated to need to be included for resetting
        int88[] memory removeDeltaLQTYVotes = new int88[](2);
        removeDeltaLQTYVotes[0] = 0;
        removeDeltaLQTYVotes[1] = 0;
        int88[] memory removeDeltaLQTYVetos = new int88[](2);

        /// @audit the next call MUST not revert - this is a critical bug
        governance.allocateLQTY(removeInitiatives, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        // After user counts LQTY the
        {
            (uint88 after_user_countedVoteLQTY, uint32 after_user_countedVoteLQTYAverageTimestamp) =
                governance.globalState();
            // The LQTY was already removed
            assertEq(after_user_countedVoteLQTY, 0, "Removal 1");
        }

        // User State allocated LQTY changes by entire previous allocation amount
        // Timestamp should not change
        {
            (uint88 after_user_allocatedLQTY,) = governance.userStates(user);
            assertEq(after_user_allocatedLQTY, 0, "Removal 2");
        }

        // Check user math only change is the LQTY amt
        // user was the only one allocated so since all alocations were reset, the initative lqty should be 0
        {
            (uint88 after_user_voteLQTY,,,,) = governance.initiativeStates(baseInitiative1);

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
        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int88[] memory deltaLQTYVetos = new int88[](2);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        (uint88 allocatedB4Test,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Test", allocatedB4Test);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory removeInitiatives = new address[](2);
        removeInitiatives[0] = baseInitiative1;
        removeInitiatives[1] = baseInitiative2;
        int88[] memory removeDeltaLQTYVotes = new int88[](2);
        // removeDeltaLQTYVotes[0] = int88(-1e18); // @audit deallocating is no longer possible
        removeDeltaLQTYVotes[0] = 0;
        int88[] memory removeDeltaLQTYVetos = new int88[](2);

        (uint88 allocatedB4Removal,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Removal", allocatedB4Removal);

        governance.allocateLQTY(removeInitiatives, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);
        (uint88 allocatedAfterRemoval,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfterRemoval", allocatedAfterRemoval);

        // @audit this test no longer reverts due to underflow because of resetting before each allocation
        // vm.expectRevert();
        governance.allocateLQTY(removeInitiatives, removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);
        (uint88 allocatedAfter,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfter", allocatedAfter);
    }

    /// Find some random amount
    /// Divide into chunks
    /// Ensure chunks above 1 wei
    /// Go ahead and remove
    /// Ensure that at the end you remove 100%
    function test_fuzz_canRemoveExtact() public {}

    function test_allocateLQTY_single() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);

        (uint88 allocatedLQTY, uint32 averageStakingTimestampUser) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint88 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = 1e18; //this should be 0
        int88[] memory deltaLQTYVetos = new int88[](1);

        // should revert if the initiative has been registered in the current epoch
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1e18);

        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
        ) = governance.initiativeStates(baseInitiative1);
        // should update the `voteLQTY` and `vetoLQTY` variables
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // should update the average staking timestamp for the initiative based on the average staking timestamp of the user's
        // voting and vetoing LQTY
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - governance.EPOCH_DURATION());
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        // should remove or add the initiatives voting LQTY from the counter

        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        uint16 atEpoch;
        (voteLQTY, vetoLQTY, atEpoch) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        // should update the allocation mapping from user to initiative
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        // should snapshot the global and initiatives votes if there hasn't been a snapshot in the current epoch yet
        (, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(forEpoch, governance.epoch() - 1);
        (, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.stopPrank();

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        (, uint32 averageAge) = governance.userStates(user2);
        assertEq(governance.lqtyToVotes(1e18, block.timestamp, averageAge), 0);

        deltaLQTYVetos[0] = 1e18;

        vm.expectRevert("Governance: vote-and-veto");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVetos[0] = 0;

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // should update the user's allocated LQTY balance
        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY,) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - governance.EPOCH_DURATION());
        assertGt(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);

        // should revert if the user doesn't have enough unallocated LQTY available
        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        // user can only unallocate after voting cutoff
        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = 0;
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 0);
        (countedVoteLQTY,) = governance.globalState();
        console.log("countedVoteLQTY: ", countedVoteLQTY);
        assertEq(countedVoteLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY,) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);

        vm.stopPrank();
    }

    function test_allocateLQTY_after_cutoff() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);

        (uint88 allocatedLQTY, uint32 averageStakingTimestampUser) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint88 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = 1e18; //this should be 0
        int88[] memory deltaLQTYVetos = new int88[](1);

        // should revert if the initiative has been registered in the current epoch
        vm.expectRevert("Governance: active-vote-fsm");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1e18);

        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
        ) = governance.initiativeStates(baseInitiative1);
        // should update the `voteLQTY` and `vetoLQTY` variables
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // should update the average staking timestamp for the initiative based on the average staking timestamp of the user's
        // voting and vetoing LQTY
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - governance.EPOCH_DURATION(), "TS");
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        // should remove or add the initiatives voting LQTY from the counter

        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        uint16 atEpoch;
        (voteLQTY, vetoLQTY, atEpoch) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        // should update the allocation mapping from user to initiative
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        // should snapshot the global and initiatives votes if there hasn't been a snapshot in the current epoch yet
        (, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(forEpoch, governance.epoch() - 1);
        (, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.stopPrank();

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        (, uint32 averageAge) = governance.userStates(user2);
        assertEq(governance.lqtyToVotes(1e18, block.timestamp, averageAge), 0);

        deltaLQTYVetos[0] = 1e18;

        vm.expectRevert("Governance: vote-and-veto");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVetos[0] = 0;

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // should update the user's allocated LQTY balance
        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY,) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - governance.EPOCH_DURATION(), "TS 2");
        assertGt(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);

        // should revert if the user doesn't have enough unallocated LQTY available
        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = 1e18;
        // should only allow for unallocating votes or allocating vetos after the epoch voting cutoff
        // vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        (allocatedLQTY,) = governance.userStates(msg.sender);
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

        (uint88 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        (uint88 countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 0);

        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 1e18;
        int88[] memory deltaLQTYVetos = new int88[](2);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 2e18);
        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 2e18);

        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
        ) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY,) =
            governance.initiativeStates(baseInitiative2);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
    }

    function test_allocateLQTY_fuzz_deltaLQTYVotes(uint88 _deltaLQTYVotes) public {
        vm.assume(_deltaLQTYVotes > 0 && _deltaLQTYVotes < uint88(type(int88).max));

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        vm.store(address(lqty), keccak256(abi.encode(user, 0)), bytes32(abi.encode(uint256(_deltaLQTYVotes))));
        lqty.approve(address(userProxy), _deltaLQTYVotes);
        governance.depositLQTY(_deltaLQTYVotes);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = int88(uint88(_deltaLQTYVotes));
        int88[] memory deltaLQTYVetos = new int88[](1);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function test_allocateLQTY_fuzz_deltaLQTYVetos(uint88 _deltaLQTYVetos) public {
        vm.assume(_deltaLQTYVetos > 0 && _deltaLQTYVetos < uint88(type(int88).max));

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        vm.store(address(lqty), keccak256(abi.encode(user, 0)), bytes32(abi.encode(uint256(_deltaLQTYVetos))));
        lqty.approve(address(userProxy), _deltaLQTYVetos);
        governance.depositLQTY(_deltaLQTYVetos);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = int88(uint88(_deltaLQTYVetos));

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        /// @audit needs overflow tests!!
        vm.stopPrank();
    }

    // forge test --match-test test_claimForInitiative -vv
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

        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int88[] memory deltaVoteLQTY = new int88[](2);
        deltaVoteLQTY[0] = 500e18;
        deltaVoteLQTY[1] = 500e18;
        int88[] memory deltaVetoLQTY = new int88[](2);
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        (uint88 allocatedLQTY,) = governance.userStates(user);
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

        console.log("here 1");
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        deltaVoteLQTY[0] = 495e18;
        // deltaVoteLQTY[1] = -495e18;
        deltaVoteLQTY[1] = 0; // @audit user can't deallocate because votes already get reset
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        console.log("here 2");

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(baseInitiative1), 10000e18);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 15000e18);

        (Governance.InitiativeStatus status,, uint256 claimable) = governance.getInitiativeState(baseInitiative2);
        console.log("res", uint8(status));
        console.log("claimable", claimable);
        (uint224 votes,,, uint224 vetos) = governance.votesForInitiativeSnapshot(baseInitiative2);
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

        address[] memory initiatives = new address[](2);
        initiatives[0] = EOAInitiative; // attempt for an EOA
        initiatives[1] = baseInitiative2;
        int88[] memory deltaVoteLQTY = new int88[](2);
        deltaVoteLQTY[0] = 500e18;
        deltaVoteLQTY[1] = 500e18;
        int88[] memory deltaVetoLQTY = new int88[](2);
        governance.allocateLQTY(initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY);
        (uint88 allocatedLQTY,) = governance.userStates(user);
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

        uint88 lqtyAmount = 1000e18;
        uint256 lqtyBalance = lqty.balanceOf(user);

        lqty.approve(address(governance.deriveUserProxyAddress(user)), lqtyAmount);

        bytes[] memory data = new bytes[](7);
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaVoteLQTY = new int88[](1);
        deltaVoteLQTY[0] = int88(uint88(lqtyAmount));
        int88[] memory deltaVetoLQTY = new int88[](1);

        int88[] memory deltaVoteLQTY_ = new int88[](1);
        deltaVoteLQTY_[0] = 0;

        data[0] = abi.encodeWithSignature("deployUserProxy()");
        data[1] = abi.encodeWithSignature("depositLQTY(uint88)", lqtyAmount);
        data[2] = abi.encodeWithSignature(
            "allocateLQTY(address[],address[],int88[],int88[])", initiatives, initiatives, deltaVoteLQTY, deltaVetoLQTY
        );
        data[3] = abi.encodeWithSignature("userStates(address)", user);
        data[4] = abi.encodeWithSignature("snapshotVotesForInitiative(address)", baseInitiative1);
        data[5] = abi.encodeWithSignature(
            "allocateLQTY(address[],address[],int88[],int88[])", initiatives, initiatives, deltaVoteLQTY_, deltaVetoLQTY
        );
        data[6] = abi.encodeWithSignature("withdrawLQTY(uint88)", lqtyAmount);
        bytes[] memory response = governance.multicall(data);

        (uint88 allocatedLQTY,) = abi.decode(response[3], (uint88, uint32));
        assertEq(allocatedLQTY, lqtyAmount);
        (IGovernance.VoteSnapshot memory votes, IGovernance.InitiativeVoteSnapshot memory votesForInitiative) =
            abi.decode(response[4], (IGovernance.VoteSnapshot, IGovernance.InitiativeVoteSnapshot));
        assertEq(votes.votes + votesForInitiative.votes, 0);
        assertEq(lqty.balanceOf(user), lqtyBalance);

        vm.stopPrank();
    }

    function test_nonReentrant() public {
        MockInitiative mockInitiative = new MockInitiative(address(governance));

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (uint240 votes, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, 1);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 2e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 2e18);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        governance.registerInitiative(address(mockInitiative));
        uint16 atEpoch = governance.registeredInitiatives(address(mockInitiative));
        assertEq(atEpoch, governance.epoch());

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(mockInitiative);
        int88[] memory deltaLQTYVotes = new int88[](1);
        int88[] memory deltaLQTYVetos = new int88[](1);
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        snapshot = IGovernance.VoteSnapshot(1, governance.epoch() - 1);
        vm.store(
            address(governance),
            bytes32(uint256(2)),
            bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes)))
        );
        (votes, forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1);
        assertEq(forEpoch, governance.epoch() - 1);

        IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot =
            IGovernance.InitiativeVoteSnapshot(1, governance.epoch() - 1, governance.epoch() - 1, 0);
        vm.store(
            address(governance),
            keccak256(abi.encode(address(mockInitiative), uint256(3))),
            bytes32(
                abi.encodePacked(
                    uint16(initiativeSnapshot.lastCountedEpoch),
                    uint16(initiativeSnapshot.forEpoch),
                    uint224(initiativeSnapshot.votes)
                )
            )
        );
        (uint224 votes_, uint16 forEpoch_, uint16 lastCountedEpoch,) =
            governance.votesForInitiativeSnapshot(address(mockInitiative));
        assertEq(votes_, 1);
        assertEq(forEpoch_, governance.epoch() - 1);
        assertEq(lastCountedEpoch, governance.epoch() - 1);

        governance.claimForInitiative(address(mockInitiative));

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        initiativeSnapshot = IGovernance.InitiativeVoteSnapshot(0, governance.epoch() - 1, 0, 0);
        vm.store(
            address(governance),
            keccak256(abi.encode(address(mockInitiative), uint256(3))),
            bytes32(
                abi.encodePacked(
                    uint16(initiativeSnapshot.lastCountedEpoch),
                    uint16(initiativeSnapshot.forEpoch),
                    uint224(initiativeSnapshot.votes)
                )
            )
        );
        (votes_, forEpoch_, lastCountedEpoch,) = governance.votesForInitiativeSnapshot(address(mockInitiative));
        assertEq(votes_, 0, "votes");
        assertEq(forEpoch_, governance.epoch() - 1, "forEpoch_");
        assertEq(lastCountedEpoch, 0, "lastCountedEpoch");

        vm.warp(block.timestamp + governance.EPOCH_DURATION() * 4);

        governance.unregisterInitiative(address(mockInitiative));
    }

    // CS exploit PoC
    function test_allocateLQTY_overflow() public {
        vm.startPrank(user);

        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;

        int88[] memory deltaLQTYVotes = new int88[](2);
        deltaLQTYVotes[0] = 0;
        deltaLQTYVotes[1] = type(int88).max;
        int88[] memory deltaLQTYVetos = new int88[](2);
        deltaLQTYVetos[0] = 0;
        deltaLQTYVetos[1] = 0;

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.expectRevert("Governance: insufficient-or-allocated-lqty");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVotes[0] = 0;
        deltaLQTYVotes[1] = 0;
        deltaLQTYVetos[0] = 0;
        deltaLQTYVetos[1] = type(int88).max;

        vm.expectRevert("Governance: insufficient-or-allocated-lqty");
        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function test_voting_power_increase() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        (uint88 allocatedLQTY0, uint32 averageStakingTimestamp0) = governance.userStates(user);
        uint240 currentUserPower0 = governance.lqtyToVotes(allocatedLQTY0, block.timestamp, averageStakingTimestamp0);

        (uint88 voteLQTY0,, uint32 averageStakingTimestampVoteLQTY0,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower0 =
            governance.lqtyToVotes(voteLQTY0, block.timestamp, averageStakingTimestampVoteLQTY0);

        // (uint224 votes, uint16 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        // console2.log("votes0: ", votes);

        // =========== epoch 2 ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // check user voting power for the current epoch
        (uint88 allocatedLQTY1, uint32 averageStakingTimestamp1) = governance.userStates(user);
        uint240 currentUserPower1 = governance.lqtyToVotes(allocatedLQTY1, block.timestamp, averageStakingTimestamp1);
        // user's allocated lqty should immediately increase their voting power
        assertGt(currentUserPower1, 0, "current user voting power is 0");

        // check initiative voting power for the current epoch
        (uint88 voteLQTY1,, uint32 averageStakingTimestampVoteLQTY1,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower1 =
            governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);
        assertGt(currentInitiativePower1, 0, "current initiative voting power is 0");
        assertEq(currentUserPower1, currentInitiativePower1, "initiative and user voting power should be equal");

        // (uint224 votes, uint16 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        // =========== epoch 2 (end) ==================
        // 3. warp to end of epoch 2 to see increase in voting power
        // NOTE: voting power increases after any amount of time because the block.timestamp passed into vote power calculation changes
        vm.warp(block.timestamp + EPOCH_DURATION - 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // user voting power should increase over a given chunk of time
        (uint88 allocatedLQTY2, uint32 averageStakingTimestamp2) = governance.userStates(user);
        uint240 currentUserPower2 = governance.lqtyToVotes(allocatedLQTY2, block.timestamp, averageStakingTimestamp2);
        assertGt(currentUserPower2, currentUserPower1);

        // initiative voting power should increase over a given chunk of time
        (uint88 voteLQTY2,, uint32 averageStakingTimestampVoteLQTY2,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower2 =
            governance.lqtyToVotes(voteLQTY2, block.timestamp, averageStakingTimestampVoteLQTY2);
        assertEq(
            currentUserPower2, currentInitiativePower2, "user power and initiative power should increase by same amount"
        );

        // votes should only get counted in the next epoch after they were allocated
        (uint224 votes, uint16 forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, 0, "votes get counted in epoch that they were allocated");

        // =========== epoch 3 ==================
        // 4. warp to third epoch and check voting power
        vm.warp(block.timestamp + 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // user voting power should increase
        (uint88 allocatedLQTY3, uint32 averageStakingTimestamp3) = governance.userStates(user);
        uint240 currentUserPower3 = governance.lqtyToVotes(allocatedLQTY3, block.timestamp, averageStakingTimestamp3);

        // votes should match the voting power for the initiative and subsequently the user since they're the only one allocated
        (uint88 voteLQTY3,, uint32 averageStakingTimestampVoteLQTY3,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower3 =
            governance.lqtyToVotes(voteLQTY3, block.timestamp, averageStakingTimestampVoteLQTY3);

        // votes should be counted in this epoch
        (votes, forEpoch,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, currentUserPower3, "initiative votes != user allocated lqty power");
        assertEq(votes, currentInitiativePower3, "initiative votes != iniative allocated lqty power");

        // TODO: check the increase in votes at the end of this epoch
        vm.warp(block.timestamp + EPOCH_DURATION - 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        (uint88 allocatedLQTY4, uint32 averageStakingTimestamp4) = governance.userStates(user);
        uint240 currentUserPower4 = governance.lqtyToVotes(allocatedLQTY4, block.timestamp, averageStakingTimestamp4);

        (uint88 voteLQTY4,, uint32 averageStakingTimestampVoteLQTY4,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower4 =
            governance.lqtyToVotes(voteLQTY4, block.timestamp, averageStakingTimestampVoteLQTY4);

        // checking if snapshotting at the end of an epoch increases the voting power
        (uint224 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, votes2, "votes for an initiative snapshot increase in same epoch");

        // =========== epoch 3 (end) ==================
    }

    // increase in user voting power and initiative voting power should be equivalent
    function test_voting_power_in_same_epoch_as_allocation() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch
        assertEq(2, governance.epoch(), "not in epoch 2");

        // check user voting power before allocation at epoch start
        (uint88 allocatedLQTY0, uint32 averageStakingTimestamp0) = governance.userStates(user);
        uint240 currentUserPower0 = governance.lqtyToVotes(allocatedLQTY0, block.timestamp, averageStakingTimestamp0);
        assertEq(currentUserPower0, 0, "user has voting power > 0");

        // check initiative voting power before allocation at epoch start
        (uint88 voteLQTY0,, uint32 averageStakingTimestampVoteLQTY0,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower0 =
            governance.lqtyToVotes(voteLQTY0, block.timestamp, averageStakingTimestampVoteLQTY0);
        assertEq(currentInitiativePower0, 0, "current initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        vm.warp(block.timestamp + (EPOCH_DURATION - 1)); // warp to end of second epoch
        assertEq(2, governance.epoch(), "not in epoch 2");

        // check user voting power after allocation at epoch end
        (uint88 allocatedLQTY1, uint32 averageStakingTimestamp1) = governance.userStates(user);
        uint240 currentUserPower1 = governance.lqtyToVotes(allocatedLQTY1, block.timestamp, averageStakingTimestamp1);
        assertGt(currentUserPower1, 0, "user has no voting power after allocation");

        // check initiative voting power after allocation at epoch end
        (uint88 voteLQTY1,, uint32 averageStakingTimestampVoteLQTY1,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower1 =
            governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);
        assertGt(currentInitiativePower1, 0, "initiative has no voting power after allocation");

        // check that user and initiative voting power is equivalent at epoch end
        assertEq(currentUserPower1, currentInitiativePower1, "currentUserPower1 != currentInitiativePower1");

        vm.warp(block.timestamp + (EPOCH_DURATION * 40));
        assertEq(42, governance.epoch(), "not in epoch 42");

        // get user voting power after multiple epochs
        (uint88 allocatedLQTY2, uint32 averageStakingTimestamp2) = governance.userStates(user);
        uint240 currentUserPower2 = governance.lqtyToVotes(allocatedLQTY2, block.timestamp, averageStakingTimestamp2);
        assertGt(currentUserPower2, currentUserPower1, "user voting power doesn't increase");

        // get initiative voting power after multiple epochs
        (uint88 voteLQTY2,, uint32 averageStakingTimestampVoteLQTY2,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower2 =
            governance.lqtyToVotes(voteLQTY2, block.timestamp, averageStakingTimestampVoteLQTY2);
        assertGt(currentInitiativePower2, currentInitiativePower1, "initiative voting power doesn't increase");

        // check that initiative and user voting always track each other
        assertEq(currentUserPower2, currentInitiativePower2, "voting powers don't match");
    }

    // initiative's increase in voting power after a snapshot is the same as the increase in power calculated using the initiative's allocation at the start and end of the epoch
    // |      deposit      |     allocate     |    snapshot     |
    // |====== epoch 1=====|==== epoch 2 =====|==== epoch 3 ====|
    function test_voting_power_increase_in_an_epoch() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // get initiative voting power at start of epoch
        (uint88 voteLQTY0,, uint32 averageStakingTimestampVoteLQTY0,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower0 =
            governance.lqtyToVotes(voteLQTY0, block.timestamp, averageStakingTimestampVoteLQTY0);
        assertEq(currentInitiativePower0, 0, "initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get initiative voting power at time of snapshot
        (uint88 voteLQTY1,, uint32 averageStakingTimestampVoteLQTY1,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower1 =
            governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);
        assertGt(currentInitiativePower1, 0, "initiative voting power is 0");

        uint240 deltaInitiativeVotingPower = currentInitiativePower1 - currentInitiativePower0;

        // 4. votes should be counted in this epoch
        (uint224 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, deltaInitiativeVotingPower, "voting power should increase by amount user allocated");
    }

    // checking that voting power calculated from lqtyAllocatedByUserToInitiative is equivalent to the voting power using values returned by userStates
    function test_voting_power_lqtyAllocatedByUserToInitiative() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative to be active
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // get user voting power at start of epoch from lqtyAllocatedByUserToInitiative
        (uint88 voteLQTY0,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp) = governance.userStates(user);
        uint240 currentInitiativePowerFrom1 =
            governance.lqtyToVotes(voteLQTY0, block.timestamp, averageStakingTimestamp);
        uint240 currentInitiativePowerFrom2 =
            governance.lqtyToVotes(allocatedLQTY, block.timestamp, averageStakingTimestamp);

        assertEq(
            currentInitiativePowerFrom1,
            currentInitiativePowerFrom2,
            "currentInitiativePowerFrom1 != currentInitiativePowerFrom2"
        );
    }

    // checking if allocating to a different initiative in a different epoch modifies the avgStakingTimestamp
    function test_average_timestamp() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 2e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // user allocates to baseInitiative1
        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 2 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp1) = governance.userStates(user);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative2 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to third epoch

        _allocateLQTYToInitiative(user, baseInitiative2, 1e18);

        // get user voting power at start of epoch 3 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp2) = governance.userStates(user);
        assertEq(averageStakingTimestamp1, averageStakingTimestamp2);
    }

    // checking if allocating to same initiative modifies the average timestamp
    // forge test --match-test test_average_timestamp_same_initiative -vv
    function test_average_timestamp_same_initiative() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 2e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // user allocates to baseInitiative1
        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 2 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp1) = governance.userStates(user);
        console2.log("averageStakingTimestamp1: ", averageStakingTimestamp1);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative1 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION + 200); // warp to third epoch

        _allocateLQTY(user, 1e18);

        // get user voting power at start of epoch 3 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp2) = governance.userStates(user);
        assertEq(averageStakingTimestamp1, averageStakingTimestamp2, "average timestamps differ");
    }

    // checking if allocating to same initiative modifies the average timestamp
    function test_average_timestamp_allocate_same_initiative_fuzz(uint256 allocateAmount) public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = uint88(allocateAmount % lqty.balanceOf(user));
        vm.assume(lqtyAmount > 0);
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // clamp lqtyAmount by half of what user staked
        uint88 lqtyAmount2 = uint88(bound(allocateAmount, 1, lqtyAmount));
        _allocateLQTY(user, lqtyAmount2);

        // get user voting power at start of epoch 2 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp1) = governance.userStates(user);

        // =========== epoch 3 (start) ==================
        // 3. user allocates to baseInitiative1 in epoch 3
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to third epoch

        // clamp lqtyAmount by amount user staked
        vm.assume(lqtyAmount > lqtyAmount2);
        vm.assume(lqtyAmount - lqtyAmount2 > 1);
        uint88 lqtyAmount3 = uint88(bound(allocateAmount, 1, lqtyAmount - lqtyAmount2));
        _allocateLQTY(user, lqtyAmount3);

        // get user voting power at start of epoch 3 from lqtyAllocatedByUserToInitiative
        (, uint32 averageStakingTimestamp2) = governance.userStates(user);
        assertEq(
            averageStakingTimestamp1, averageStakingTimestamp2, "averageStakingTimestamp1 != averageStakingTimestamp2"
        );
    }

    function test_voting_snapshot_start_vs_end_epoch() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        // get initiative voting power at start of epoch
        (uint88 voteLQTY0,, uint32 averageStakingTimestampVoteLQTY0,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower0 =
            governance.lqtyToVotes(voteLQTY0, block.timestamp, averageStakingTimestampVoteLQTY0);
        assertEq(currentInitiativePower0, 0, "initiative voting power is > 0");

        _allocateLQTY(user, lqtyAmount);

        uint256 stateBeforeSnapshottingVotes = vm.snapshot();

        // =========== epoch 3 (start) ==================
        // 3a. warp to start of third epoch
        vm.warp(block.timestamp + EPOCH_DURATION);
        assertEq(3, governance.epoch(), "not in 3rd epoch");
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get initiative voting power at start of epoch
        (uint88 voteLQTY1,, uint32 averageStakingTimestampVoteLQTY1,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower1 =
            governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);

        // 4a. votes from snapshotting at begging of epoch
        (uint224 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        console2.log("currentInitiativePower1: ", currentInitiativePower1);
        console2.log("votes: ", votes);

        // =========== epoch 3 (end) ==================
        // revert EVM to state before snapshotting
        vm.revertTo(stateBeforeSnapshottingVotes);

        // 3b. warp to end of third epoch
        vm.warp(block.timestamp + (EPOCH_DURATION * 2) - 1);
        assertEq(3, governance.epoch(), "not in 3rd epoch");
        governance.snapshotVotesForInitiative(baseInitiative1);

        // 4b. votes from snapshotting at end of epoch
        (uint224 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, votes2, "votes from snapshot are dependent on time at snapshot");
    }

    // checks that there's no difference to resulting voting power from allocating at start or end of epoch
    function test_voting_power_no_difference_in_allocating_start_or_end_of_epoch() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes liquity
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        uint256 stateBeforeAllocation = vm.snapshot();

        // =========== epoch 2 (start) ==================
        // 2a. user allocates at start of epoch 2
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3a. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get voting power from allocation in previous epoch
        (uint224 votesFromAllocatingAtEpochStart,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);

        // ========================================
        // ===== revert to initial state ==========
        // ========================================

        // ===============  epoch 1 ===============
        // revert EVM to state before allocation
        vm.revertTo(stateBeforeAllocation);

        // ===============  epoch 2 (end - just before cutoff) ===============
        // 2b. user allocates at end of epoch 2
        vm.warp(block.timestamp + (EPOCH_DURATION * 2) - governance.EPOCH_VOTING_CUTOFF()); // warp to end of second epoch before the voting cutoff

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3b. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        governance.snapshotVotesForInitiative(baseInitiative1);

        // get voting power from allocation in previous epoch
        (uint224 votesFromAllocatingAtEpochEnd,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(
            votesFromAllocatingAtEpochStart,
            votesFromAllocatingAtEpochEnd,
            "allocating is more favorable at certain point in epoch"
        );
    }

    // deallocating is correctly reflected in voting power for next epoch
    function test_voting_power_decreases_next_epoch() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
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
        (uint224 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertGt(votes, 0, "voting power should increase");

        _deAllocateLQTY(user, 0);

        governance.snapshotVotesForInitiative(baseInitiative1);

        // 5. votes should still be counted in this epoch
        (uint224 votes2,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertGt(votes2, 0, "voting power should not decrease this epoch");

        // =========== epoch 4 ==================
        vm.warp(block.timestamp + EPOCH_DURATION);
        console2.log("current epoch B: ", governance.epoch());
        governance.snapshotVotesForInitiative(baseInitiative1);

        // 6. votes should be decreased in this epoch
        (uint224 votes3,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes3, 0, "voting power should be decreased in this epoch");
    }

    // checking if deallocating changes the averageStakingTimestamp
    function test_deallocating_decreases_avg_timestamp() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
        _stakeLQTY(user, lqtyAmount);

        // =========== epoch 2 (start) ==================
        // 2. user allocates in epoch 2 for initiative
        vm.warp(block.timestamp + EPOCH_DURATION); // warp to second epoch

        _allocateLQTY(user, lqtyAmount);

        // =========== epoch 3 ==================
        // 3. warp to third epoch and check voting power
        vm.warp(block.timestamp + EPOCH_DURATION);
        governance.snapshotVotesForInitiative(baseInitiative1);

        (, uint32 averageStakingTimestampBefore) = governance.userStates(user);

        _deAllocateLQTY(user, 0);

        (, uint32 averageStakingTimestampAfter) = governance.userStates(user);
        assertEq(averageStakingTimestampBefore, averageStakingTimestampAfter);
    }

    // vetoing shouldn't affect voting power of the initiative
    function test_vote_and_veto() public {
        // =========== epoch 1 ==================
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
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
                epochStart: uint32(block.timestamp),
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            address(this),
            initialInitiatives
        );

        // 1. user stakes lqty
        uint88 lqtyAmount = 1e18;
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
        (uint88 voteLQTY,, uint32 averageStakingTimestampVoteLQTY,,) = governance.initiativeStates(baseInitiative1);
        uint240 currentInitiativePower =
            governance.lqtyToVotes(voteLQTY, block.timestamp, averageStakingTimestampVoteLQTY);

        // 4. votes should not affect accounting for votes
        (uint224 votes,,,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(votes, currentInitiativePower, "voting power of initiative should not be affected by vetos");
    }

    function _stakeLQTY(address staker, uint88 amount) internal {
        vm.startPrank(staker);
        address userProxy = governance.deriveUserProxyAddress(staker);
        lqty.approve(address(userProxy), amount);

        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocateLQTY(address allocator, uint88 amount) internal {
        vm.startPrank(allocator);

        // always pass all possible initiatives to deregister for simplicity
        address[] memory initiativesToDeRegister = new address[](4);
        initiativesToDeRegister[0] = baseInitiative1;
        initiativesToDeRegister[1] = baseInitiative2;
        initiativesToDeRegister[2] = baseInitiative3;
        initiativesToDeRegister[3] = address(0x123123);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = int88(amount);
        int88[] memory deltaLQTYVetos = new int88[](1);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _allocateLQTYToInitiative(address allocator, address initiative, uint88 amount) internal {
        vm.startPrank(allocator);

        address[] memory initiativesToDeRegister = new address[](4);
        initiativesToDeRegister[0] = baseInitiative1;
        initiativesToDeRegister[1] = baseInitiative2;
        initiativesToDeRegister[2] = baseInitiative3;
        initiativesToDeRegister[3] = address(0x123123);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = int88(amount);
        int88[] memory deltaLQTYVetos = new int88[](1);

        governance.allocateLQTY(initiativesToDeRegister, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _veto(address allocator, uint88 amount) internal {
        vm.startPrank(allocator);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        int88[] memory deltaLQTYVetos = new int88[](1);
        deltaLQTYVetos[0] = int88(amount);

        governance.allocateLQTY(initiatives, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }

    function _deAllocateLQTY(address allocator, uint88 amount) internal {
        vm.startPrank(allocator);

        address[] memory initiativesToDeRegister = new address[](4);
        initiativesToDeRegister[0] = baseInitiative1;
        initiativesToDeRegister[1] = baseInitiative2;
        initiativesToDeRegister[2] = baseInitiative3;
        initiativesToDeRegister[3] = address(0x123123);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int88[] memory deltaLQTYVotes = new int88[](1);
        deltaLQTYVotes[0] = -int88(amount);
        int88[] memory deltaLQTYVetos = new int88[](1);

        governance.allocateLQTY(initiativesToDeRegister, initiatives, deltaLQTYVotes, deltaLQTYVetos);
        vm.stopPrank();
    }
}
