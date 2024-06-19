// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// import {console} from "forge-std/console.sol";

import {StakingV2} from "../src/StakingV2.sol";
import {Voting} from "../src/Voting.sol";

contract VotingTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC); // Binance wallet
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);
    address private constant initiative2 = address(0x2);

    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant REGISTRATION_FEE = 0;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Voting private voting;
    StakingV2 private stakingV2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        address _voting = vm.computeCreateAddress(address(this), 2);
        stakingV2 = new StakingV2(address(lqty), address(lusd), stakingV1, _voting);
        voting = new Voting(
            address(stakingV2),
            address(lusd),
            MIN_CLAIM,
            MIN_ACCRUAL,
            REGISTRATION_FEE,
            block.timestamp,
            EPOCH_DURATION,
            EPOCH_VOTING_CUTOFF
        );
    }

    function test_epoch() public {
        assertEq(voting.epoch(), 1);

        vm.warp(block.timestamp + 7 days - 1);
        assertEq(voting.epoch(), 1);

        vm.warp(block.timestamp + 1);
        assertEq(voting.epoch(), 2);

        vm.warp(block.timestamp + 3653 days - 7 days);
        assertEq(voting.epoch(), 522); // number of weeks + 1
    }

    function test_sharesToVotes() public {
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 0);

        vm.warp(block.timestamp + 365 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 1e18);

        vm.warp(block.timestamp + 730 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 3e18);

        vm.warp(block.timestamp + 1095 days);
        assertEq(voting.sharesToVotes(stakingV2.currentShareRate(), 1e18), 6e18);
    }

    function test_calculateVotingThreshold() public {
        voting = new Voting(
            address(stakingV2),
            address(lusd),
            MIN_CLAIM,
            MIN_ACCRUAL,
            REGISTRATION_FEE,
            block.timestamp,
            EPOCH_DURATION,
            EPOCH_VOTING_CUTOFF
        );

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        Voting.Snapshot memory snapshot = Voting.Snapshot(1e18, 1);
        vm.store(address(voting), bytes32(uint256(2)), bytes32(abi.encode(snapshot)));
        (uint240 votes,) = voting.votesSnapshot();
        assertEq(votes, 1e18);

        uint256 boldAccrued = 1000e18;
        vm.store(address(voting), bytes32(uint256(7)), bytes32(abi.encode(boldAccrued)));
        assertEq(voting.boldAccrued(), 1000e18);

        assertEq(voting.calculateVotingThreshold(), MIN_CLAIM / 1000);

        // check that votingThreshold is 4% of votes of previous epoch
        voting = new Voting(
            address(stakingV2),
            address(lusd),
            10e18,
            10e18,
            REGISTRATION_FEE,
            block.timestamp,
            EPOCH_DURATION,
            EPOCH_VOTING_CUTOFF
        );

        snapshot = Voting.Snapshot(10000e18, 1);
        vm.store(address(voting), bytes32(uint256(2)), bytes32(abi.encode(snapshot)));
        (votes,) = voting.votesSnapshot();
        assertEq(votes, 10000e18);

        boldAccrued = 1000e18;
        vm.store(address(voting), bytes32(uint256(7)), bytes32(abi.encode(boldAccrued)));
        assertEq(voting.boldAccrued(), 1000e18);

        assertEq(voting.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    function test_registerInitiative() public {
        voting.registerInitiative(initiative);
        assertEq(voting.initiativesRegistered(initiative), block.timestamp);
    }

    function test_allocateShares() public {
        voting.registerInitiative(initiative);

        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(stakingV2.depositLQTY(1e18), 1e18);

        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = 1e18;
        int256[] memory deltaVetoShares = new int256[](1);

        vm.expectRevert("Voting: initiative-not-active");
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + 365 days);
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(voting.qualifyingShares(), 1e18);
        assertEq(voting.sharesAllocatedByUser(user), 1e18);

        vm.expectRevert("StakingV2: insufficient-unallocated-shares");
        stakingV2.withdrawShares(1e18);

        vm.warp(block.timestamp + voting.secondsUntilNextEpoch() - 1);

        initiatives[0] = initiative;
        deltaShares[0] = 1e18;
        vm.expectRevert("Voting: epoch-voting-cutoff");
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);

        initiatives[0] = initiative;
        deltaShares[0] = -1e18;
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        vm.stopPrank();
    }

    function test_claimForInitiative() public {
        voting.registerInitiative(initiative);
        voting.registerInitiative(initiative2);

        vm.startPrank(user);

        // deploy
        address userProxy = stakingV2.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        assertEq(stakingV2.depositLQTY(1000e18), 1000e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(voting.qualifyingShares(), 0);
        assertEq(voting.sharesAllocatedByUser(user), 0);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(voting), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](2);
        initiatives[0] = initiative;
        initiatives[1] = initiative2;
        int256[] memory deltaShares = new int256[](2);
        deltaShares[0] = 500e18;
        deltaShares[1] = 500e18;
        int256[] memory deltaVetoShares = new int256[](2);
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);
        assertEq(voting.qualifyingShares(), 1000e18);
        assertEq(voting.sharesAllocatedByUser(user), 1000e18);

        vm.warp(block.timestamp + voting.EPOCH_DURATION() + 1);

        assertEq(voting.claimForInitiative(initiative), 5000e18);
        assertEq(voting.claimForInitiative(initiative), 0);

        assertEq(voting.claimForInitiative(initiative2), 5000e18);
        assertEq(voting.claimForInitiative(initiative2), 0);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(voting), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiatives[0] = initiative;
        initiatives[1] = initiative2;
        deltaShares[0] = 495e18;
        deltaShares[1] = -495e18;
        voting.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + voting.EPOCH_DURATION() + 1);

        assertEq(voting.claimForInitiative(initiative), 10000e18);
        assertEq(voting.claimForInitiative(initiative), 0);

        assertEq(voting.claimForInitiative(initiative2), 0);
        assertEq(voting.claimForInitiative(initiative2), 0);

        vm.stopPrank();
    }
}
