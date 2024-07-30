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
    GovernanceInternal private governanceInternal;
    address[] private initialInitiatives;

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

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
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
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
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
    }

    function test_averageAge(uint32 _currentTimestamp, uint32 _timestamp) public {
        uint32 averageAge = governanceInternal.averageAge(_currentTimestamp, _timestamp);
        if (_timestamp == 0 || _currentTimestamp < _timestamp) {
            assertEq(averageAge, 0);
        } else {
            assertEq(averageAge, _currentTimestamp - _timestamp);
        }
    }

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

        // check address
        address userProxy = governance.deriveUserProxyAddress(user);

        // deploy and deposit 1 LQTY
        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 1e18);
        (uint88 allocatedLQTY, uint32 averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        assertEq(averageStakingTimestamp, block.timestamp);

        vm.warp(block.timestamp + timeIncrease);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        assertEq(UserProxy(payable(userProxy)).staked(), 2e18);
        (allocatedLQTY, averageStakingTimestamp) = governance.userStates(user);
        assertEq(allocatedLQTY, 0);
        assertEq(averageStakingTimestamp, block.timestamp - timeIncrease / 2);

        // withdraw 0.5 half of LQTY
        vm.warp(block.timestamp + timeIncrease);
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
        permitParams.s = s;

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

    function test_epoch() public {
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 7 days - 1);
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 1);
        assertEq(governance.epoch(), 2);

        vm.warp(block.timestamp + 3653 days - 7 days);
        assertEq(governance.epoch(), 522); // number of weeks + 1
    }

    function test_epochStart() public {
        assertEq(governance.epochStart(), block.timestamp);
        vm.warp(block.timestamp + 1);
        assertEq(governance.epochStart(), block.timestamp - 1);
    }

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
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(address(governance), bytes32(uint256(2)), bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes))));
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
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                unregistrationThresholdFactor: UNREGISTRATION_THRESHOLD_FACTOR,
                unregistrationAfterEpochs: UNREGISTRATION_AFTER_EPOCHS,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: 10e18,
                minAccrual: 10e18,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );

        snapshot = IGovernance.VoteSnapshot(10000e18, 1);
        vm.store(address(governance), bytes32(uint256(2)), bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes))));
        (votes, forEpoch) = governance.votesSnapshot();
        assertEq(votes, 10000e18);
        assertEq(forEpoch, 1);

        boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(1)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    function test_registerInitiative() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(address(governance), bytes32(uint256(2)), bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes))));
        (uint240 votes,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.registerInitiative(baseInitiative3);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 1e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 1e18);

        vm.expectRevert("Governance: insufficient-lqty");
        governance.registerInitiative(baseInitiative3);

        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + 365 days);

        governance.registerInitiative(baseInitiative3);
        uint16 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        vm.stopPrank();
    }

    function test_unregisterInitiative() public {
        vm.startPrank(user);

        address userProxy = governance.deployUserProxy();

        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1);
        vm.store(address(governance), bytes32(uint256(2)), bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes))));
        (uint240 votes, uint16 forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, 1);

        vm.startPrank(lusdHolder);
        lusd.transfer(user, 1e18);
        vm.stopPrank();

        vm.startPrank(user);

        lusd.approve(address(governance), 1e18);
        lqty.approve(address(userProxy), 1e18);
        governance.depositLQTY(1e18);
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert("Governance: initiative-not-registered");
        governance.unregisterInitiative(baseInitiative3);

        governance.registerInitiative(baseInitiative3);
        uint16 atEpoch = governance.registeredInitiatives(baseInitiative3);
        assertEq(atEpoch, governance.epoch());

        // voting threshold

        snapshot = IGovernance.VoteSnapshot(1e18, governance.epoch() - 1);
        vm.store(address(governance), bytes32(uint256(2)), bytes32(abi.encodePacked(uint16(snapshot.forEpoch), uint240(snapshot.votes))));
        (votes, forEpoch) = governance.votesSnapshot();
        assertEq(votes, 1e18);
        assertEq(forEpoch, governance.epoch() - 1);

        IGovernance.InitiativeVoteSnapshot memory initiativeSnapshot = IGovernance.InitiativeVoteSnapshot(0, governance.epoch() - 1, 0);
        vm.store(address(governance), keccak256(abi.encode(baseInitiative3, uint256(3))), bytes32(abi.encodePacked(uint16(initiativeSnapshot.lastCountedEpoch), uint16(initiativeSnapshot.forEpoch), uint240(initiativeSnapshot.votes))));
        (uint224 votes_, uint16 forEpoch_, uint16 lastCountedEpoch) = governance.votesForInitiativeSnapshot(baseInitiative3);
        assertEq(votes_, 0);
        assertEq(forEpoch_, governance.epoch() - 1);
        assertEq(lastCountedEpoch, 0);

        governance.unregisterInitiative(baseInitiative3);

        vm.stopPrank();
    }

    // function test_snapshotVotesForInitiative() public {}

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
            uint16 counted
        ) = governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - 365 days);
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        assertEq(counted, 1);

        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        uint16 atEpoch;
        (voteLQTY, vetoLQTY, atEpoch) = governance.lqtyAllocatedByUserToInitiative(user, baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(user2);

        address user2Proxy = governance.deployUserProxy();

        lqty.approve(address(user2Proxy), 1e18);
        governance.depositLQTY(1e18);

        (, uint32 averageAge) = governance.userStates(user2);
        assertEq(governance.lqtyToVotes(1e18, block.timestamp, averageAge), 0);

        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY, counted) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 2e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, block.timestamp - 365 days);
        assertGt(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        assertEq(counted, 1);

        vm.expectRevert("Governance: insufficient-unallocated-lqty");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + EPOCH_DURATION - governance.secondsWithinEpoch() - 1);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = 1e18;
        vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        initiatives[0] = baseInitiative1;
        deltaLQTYVotes[0] = -1e18;
        governance.allocateLQTY(initiatives, deltaLQTYVotes, deltaLQTYVetos);

        (allocatedLQTY,) = governance.userStates(user2);
        assertEq(allocatedLQTY, 0);
        (countedVoteLQTY,) = governance.globalState();
        assertEq(countedVoteLQTY, 1e18);

        (voteLQTY, vetoLQTY, averageStakingTimestampVoteLQTY, averageStakingTimestampVetoLQTY, counted) =
            governance.initiativeStates(baseInitiative1);
        assertEq(voteLQTY, 1e18);
        assertEq(vetoLQTY, 0);
        assertEq(averageStakingTimestampVoteLQTY, averageStakingTimestampUser);
        assertEq(averageStakingTimestampVetoLQTY, 0);
        assertEq(counted, 1);

        // console.logBytes32(vm.load(address(governance), bytes32(uint256(2))));

        vm.stopPrank();
    }

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

        assertEq(governance.claimForInitiative(baseInitiative1), 5000e18);
        governance.claimForInitiative(baseInitiative1);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 5000e18);

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

        assertEq(governance.claimForInitiative(baseInitiative1), 10000e18);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 15000e18);

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
}
