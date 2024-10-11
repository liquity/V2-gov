// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
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
    ) Governance(_lqty, _lusd, _stakingV1, _bold, _config, _initiatives) {}

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

    function test_calculateVotingThreshold() public {
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
            initialInitiatives
        );

        // is 0 when the previous epochs votes are 0
        assertEq(governance.calculateVotingThreshold(), 0);

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

        assertEq(governance.calculateVotingThreshold(), MIN_CLAIM / 1000);

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

        assertEq(governance.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    // should not revert under any state
    function test_calculateVotingThreshold_fuzz(
        uint128 _votes,
        uint16 _forEpoch,
        uint88 _boldAccrued,
        uint128 _votingThresholdFactor,
        uint88 _minClaim
    ) public {
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

        governance.calculateVotingThreshold();
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
        vm.warp(block.timestamp + 365 days);

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
        vm.warp(block.timestamp + 365 days);

        // should revert if the initiative isn't registered
        vm.expectRevert("Governance: initiative-not-registered");
        governance.unregisterInitiative(baseInitiative3);
        
        governance.registerInitiative(baseInitiative3);
        uint16 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        // should revert if the initiative is still in the registration warm up period
        vm.expectRevert("Governance: initiative-in-warm-up");
        governance.unregisterInitiative(baseInitiative3);

        vm.warp(block.timestamp + 365 days);

        // should revert if the initiative is still active or the vetos don't meet the threshold
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

        IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot =
            IGovernance.InitiativeVoteSnapshot(0, governance.epoch() - 1, 0);
        vm.store(
            address(governance),
            keccak256(abi.encode(baseInitiative3, uint256(3))),
            bytes32(
                abi.encodePacked(
                    uint16(initiativeSnapshot.lastCountedEpoch),
                    uint16(initiativeSnapshot.forEpoch),
                    uint224(initiativeSnapshot.votes)
                )
            )
        );
        (uint224 votes_, uint16 forEpoch_, uint16 lastCountedEpoch) =
            governance.votesForInitiativeSnapshot(baseInitiative3);
        assertEq(votes_, 0);
        assertEq(forEpoch_, governance.epoch() - 1);
        assertEq(lastCountedEpoch, 0);

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
        int176[] memory deltaLQTYVotes = new int176[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int176[] memory deltaLQTYVetos = new int176[](2);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (uint256 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1_000e18);

        (
            uint88 voteLQTY1,
            ,
            uint32 averageStakingTimestampVoteLQTY1,
            ,
            uint16 counted1, 
        ) = governance.initiativeStates(baseInitiative1);

        (
            uint88 voteLQTY2,
            ,
            ,
            ,
            uint16 counted2, 
        ) = governance.initiativeStates(baseInitiative2);

        // Get power at time of vote
        uint256 votingPower = governance.lqtyToVotes(voteLQTY1, block.timestamp, averageStakingTimestampVoteLQTY1);
        assertGt(votingPower, 0, "Non zero power");
        
        /// @audit TODO Fully digest and explain the bug
        // Warp to end so we check the threshold against future threshold
        
        {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());

            (IGovernance.VoteSnapshot memory snapshot, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot1) = governance.snapshotVotesForInitiative(baseInitiative1);
            (, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot2) = governance.snapshotVotesForInitiative(baseInitiative2);


        (
            ,
            ,
            ,
            ,
            uint16 counted1again, 
        ) = governance.initiativeStates(baseInitiative1);
            assertEq(counted1, 1, "1 is counted inspite below voting");
            assertEq(counted1again, 1, "Counted is true");
            uint256 threshold = governance.calculateVotingThreshold();
            assertEq(initiativeVoteSnapshot1.votes, 0, "it didn't get votes");

            uint256 votingPowerWithProjection = governance.lqtyToVotes(voteLQTY1, governance.epochStart() + governance.EPOCH_DURATION(), averageStakingTimestampVoteLQTY1);
            assertLt(votingPower, threshold, "Current Power is not enough - Desynch A");
            assertLt(votingPowerWithProjection, threshold, "Future Power is also not enough - Desynch B");

            assertEq(counted1, counted2, "both counted");
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
        int176[] memory deltaLQTYVotes = new int176[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int176[] memory deltaLQTYVetos = new int176[](2);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

    
        // Warp to end so we check the threshold against future threshold
        
        {
            vm.warp(block.timestamp + governance.EPOCH_DURATION());

            (IGovernance.VoteSnapshot memory snapshot, IGovernance.InitiativeVoteSnapshot memory initiativeVoteSnapshot1) = governance.snapshotVotesForInitiative(baseInitiative1);

            uint256 threshold = governance.calculateVotingThreshold();
            assertEq(initiativeVoteSnapshot1.votes, 0, "it didn't get votes");
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
        address[] memory removeInitiatives = new address[](1);
        removeInitiatives[0] = baseInitiative1;
        int176[] memory removeDeltaLQTYVotes = new int176[](1);
        removeDeltaLQTYVotes[0] = -1e18;
        int176[] memory removeDeltaLQTYVetos = new int176[](1);

        /// @audit the next call MUST not revert - this is a critical bug
        governance.allocateLQTY(removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);

        // Security Check | TODO: MORE INVARIANTS
        // I should not be able to remove votes again
        vm.expectRevert(); // TODO: This is a panic
        governance.allocateLQTY(removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);


        address[] memory reAddInitiatives = new address[](1);
        reAddInitiatives[0] = baseInitiative1;
        int176[] memory reAddDeltaLQTYVotes = new int176[](1);
        reAddDeltaLQTYVotes[0] = 1e18;
        int176[] memory reAddDeltaLQTYVetos = new int176[](1);

        /// @audit This MUST revert, an initiative should not be re-votable once disabled
        vm.expectRevert("Governance: initiative-not-active");
        governance.allocateLQTY(reAddInitiatives, reAddDeltaLQTYVotes, reAddDeltaLQTYVetos);
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
        int176[] memory deltaLQTYVotes = new int176[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 999e18;
        int176[] memory deltaLQTYVetos = new int176[](2);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);
        (uint88 allocatedB4Test,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Test", allocatedB4Test);

        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());
        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        address[] memory removeInitiatives = new address[](1);
        removeInitiatives[0] = baseInitiative1;
        int176[] memory removeDeltaLQTYVotes = new int176[](1);
        removeDeltaLQTYVotes[0] = int176(-1e18);
        int176[] memory removeDeltaLQTYVetos = new int176[](1);

        (uint88 allocatedB4Removal,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedB4Removal", allocatedB4Removal);

        governance.allocateLQTY(removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);
        (uint88 allocatedAfterRemoval,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfterRemoval", allocatedAfterRemoval);

        vm.expectRevert();
        governance.allocateLQTY(removeInitiatives, removeDeltaLQTYVotes, removeDeltaLQTYVetos);
        (uint88 allocatedAfter,,) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        console.log("allocatedAfter", allocatedAfter);
    }

    /// Find some random amount
    /// Divide into chunks
    /// Ensure chunks above 1 wei
    /// Go ahead and remove
    /// Ensure that at the end you remove 100%
    function test_fuzz_canRemoveExtact() public {

    }

    function test_allocateLQTY() public {
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
        int176[] memory deltaLQTYVotes = new int176[](1);
        deltaLQTYVotes[0] = 1e18;
        int176[] memory deltaLQTYVetos = new int176[](1);

        // should revert if the initiative has been registered in the current epoch
        vm.expectRevert("Governance: initiative-not-active");
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.warp(block.timestamp + 365 days);
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1e18);

        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
            uint16 counted, 
        ) = governance.initiativeStates(baseInitiative1);
        // should update the `voteLQTY` and `vetoLQTY` variables
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        // should update the average staking timestamp for the initiative based on the average staking timestamp of the user's
        // voting and vetoing LQTY
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - 365 days);
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        // should remove or add the initiatives voting LQTY from the counter
        assertEq(counted, 1);
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
        (, forEpoch,) = governance.votesForInitiativeSnapshot(baseInitiative1);
        assertEq(forEpoch, governance.epoch() - 1);

        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        (, uint32 averageAge) = governance.userStates(user2);
        assertEq(governance.lqtyToVotes(1e18, block.timestamp, averageAge), 0);

        deltaLQTYVetos[0] = 1e18;

        vm.expectRevert("Governance: vote-and-veto");
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        deltaLQTYVetos[0] = 0;

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        // should update the user's allocated LQTY balance
        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY, counted, ) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - 365 days);
        assertGt(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        assertEq(counted, 1);

        // should revert if the user doesn't have enough unallocated LQTY available
        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = 1e18;
        // should only allow for unallocating votes or allocating vetos after the epoch voting cutoff
        vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = -1e18;
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 0);
        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY, counted, ) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        assertEq(counted, 1);

        vm.stopPrank();
    }

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
        int176[] memory deltaLQTYVotes = new int176[](2);
        deltaLQTYVotes[0] = 1e18;
        deltaLQTYVotes[1] = 1e18;
        int176[] memory deltaLQTYVetos = new int176[](2);

        vm.warp(block.timestamp + 365 days);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 2e18);
        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 2e18);

        (
            uint88 voteLQTY,
            uint88 vetoLQTY,
            uint32 averageStakingTimestampVoteLQTY,
            uint32 averageStakingTimestampVetoLQTY,
            uint16 counted, 
        ) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY, counted, ) =
            governance.initiativeStates(baseInitiative2);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
    }

    function test_allocateLQTY_fuzz_deltaLQTYVotes(uint88 _deltaLQTYVotes) public {
        vm.assume(_deltaLQTYVotes > 0);

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        vm.store(address(lqty), keccak256(abi.encode(user, 0)), bytes32(abi.encode(uint256(_deltaLQTYVotes))));
        lqty.approve(address(userProxy), _deltaLQTYVotes);
        governance.depositLQTY(_deltaLQTYVotes);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int176[] memory deltaLQTYVotes = new int176[](1);
        deltaLQTYVotes[0] = int176(uint176(_deltaLQTYVotes));
        int176[] memory deltaLQTYVetos = new int176[](1);

        vm.warp(block.timestamp + 365 days);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        vm.stopPrank();
    }

    function test_allocateLQTY_fuzz_deltaLQTYVetos(uint88 _deltaLQTYVetos) public {
        vm.assume(_deltaLQTYVetos > 0);

        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        vm.store(address(lqty), keccak256(abi.encode(user, 0)), bytes32(abi.encode(uint256(_deltaLQTYVetos))));
        lqty.approve(address(userProxy), _deltaLQTYVetos);
        governance.depositLQTY(_deltaLQTYVetos);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int176[] memory deltaLQTYVotes = new int176[](1);
        int176[] memory deltaLQTYVetos = new int176[](1);
        deltaLQTYVetos[0] = int176(uint176(_deltaLQTYVetos));

        vm.warp(block.timestamp + 365 days);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);
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

        vm.warp(block.timestamp + 365 days);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int176[] memory deltaVoteLQTY = new int176[](2);
        deltaVoteLQTY[0] = 500e18;
        deltaVoteLQTY[1] = 500e18;
        int176[] memory deltaVetoLQTY = new int176[](2);
        governance.allocateLQTY(initiatives, deltaVoteLQTY, deltaVetoLQTY);
        (uint88 allocatedLQTY,) = governance.userStates(user);
        assertEq(allocatedLQTY, 1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        // should compute the claim and transfer it to the initiative
        assertEq(governance.claimForInitiative(baseInitiative1), 5000e18);
        // 2nd claim = 0
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(governance.claimForInitiative(baseInitiative2), 5000e18);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        deltaVoteLQTY[0] = 495e18;
        deltaVoteLQTY[1] = -495e18;
        governance.allocateLQTY(initiatives, deltaVoteLQTY, deltaVetoLQTY);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        /// @audit this fails, because by counting 100% of votes, the ones that don't make it steal the yield
        /// This is MED at most, in this test a 50 BPS loss
        /// Due to this, we'll acknowledge it for now
        assertEq(governance.claimForInitiative(baseInitiative1), 9950e18);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);


        assertEq(lusd.balanceOf(baseInitiative1), 14950e18);

        assertEq(governance.claimForInitiative(baseInitiative2), 0);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();
    }

    function test_multicall() public {
        vm.startPrank(user);

        vm.warp(block.timestamp + 365 days);

        uint88 lqtyAmount = 1000e18;
        uint256 lqtyBalance = lqty.balanceOf(user);

        lqty.approve(address(governance.deriveUserProxyAddress(user)), lqtyAmount);

        bytes[] memory data = new bytes[](7);
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int176[] memory deltaVoteLQTY = new int176[](1);
        deltaVoteLQTY[0] = int176(uint176(lqtyAmount));
        int176[] memory deltaVetoLQTY = new int176[](1);

        int176[] memory deltaVoteLQTY_ = new int176[](1);
        deltaVoteLQTY_[0] = -int176(uint176(lqtyAmount));

        data[0] = abi.encodeWithSignature("deployUserProxy()");
        data[1] = abi.encodeWithSignature("depositLQTY(uint88)", lqtyAmount);
        data[2] = abi.encodeWithSignature(
            "allocateLQTY(address[],int176[],int176[])", initiatives, deltaVoteLQTY, deltaVetoLQTY
        );
        data[3] = abi.encodeWithSignature("userStates(address)", user);
        data[4] = abi.encodeWithSignature("snapshotVotesForInitiative(address)", baseInitiative1);
        data[5] = abi.encodeWithSignature(
            "allocateLQTY(address[],int176[],int176[])", initiatives, deltaVoteLQTY_, deltaVetoLQTY
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
        vm.warp(block.timestamp + 365 days);

        governance.registerInitiative(address(mockInitiative));
        uint16 atEpoch = governance.registeredInitiatives(address(mockInitiative));
        assertEq(atEpoch, governance.epoch());

        vm.warp(block.timestamp + 365 days);

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(mockInitiative);
        int176[] memory deltaLQTYVotes = new int176[](1);
        int176[] memory deltaLQTYVetos = new int176[](1);
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

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
            IGovernance.InitiativeVoteSnapshot(1, governance.epoch() - 1, governance.epoch() - 1);
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
        (uint224 votes_, uint16 forEpoch_, uint16 lastCountedEpoch) =
            governance.votesForInitiativeSnapshot(address(mockInitiative));
        assertEq(votes_, 1);
        assertEq(forEpoch_, governance.epoch() - 1);
        assertEq(lastCountedEpoch, governance.epoch() - 1);

        governance.claimForInitiative(address(mockInitiative));

        vm.warp(block.timestamp + governance.EPOCH_DURATION());

        initiativeSnapshot = IGovernance.InitiativeVoteSnapshot(0, governance.epoch() - 1, 0);
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
        (votes_, forEpoch_, lastCountedEpoch) = governance.votesForInitiativeSnapshot(address(mockInitiative));
        assertEq(votes_, 0);
        assertEq(forEpoch_, governance.epoch() - 1);
        assertEq(lastCountedEpoch, 0);

        governance.unregisterInitiative(address(mockInitiative));
    }
}
