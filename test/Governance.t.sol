// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
// import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {Governance} from "../src/Governance.sol";
import {WAD, PermitParams} from "../src/utils/Types.sol";

interface ILQTY {
    function domainSeparator() external view returns (bytes32);
}

contract GovernanceTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
    address private constant initiative = address(0x1);
    address private constant initiative2 = address(0x2);
    address private constant initiative3 = address(0x3);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

    Governance private governance;
    address[] private initialInitiatives;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        initialInitiatives.push(initiative);
        initialInitiatives.push(initiative2);

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
    }

    function test_deployUserProxy() public {
        address userProxy = governance.deriveUserProxyAddress(user);

        vm.startPrank(user);
        assertEq(governance.deployUserProxy(), userProxy);
        vm.expectRevert();
        governance.deployUserProxy();
        vm.stopPrank();

        governance.deployUserProxy();
        assertEq(governance.deriveUserProxyAddress(user), userProxy);
    }

    function test_depositLQTY_withdrawShares() public {
        vm.startPrank(user);

        // check address
        address userProxy = governance.deriveUserProxyAddress(user);

        // deploy and deposit 1 LQTY
        lqty.approve(address(userProxy), 1e18);
        assertEq(governance.depositLQTY(1e18), 1e18);
        assertEq(governance.sharesByUser(user), 1e18);

        // deposit 2 LQTY
        vm.warp(block.timestamp + 86400 * 30);
        lqty.approve(address(userProxy), 2e18);
        assertEq(governance.depositLQTY(2e18), 2e18 * WAD / governance.currentShareRate());
        assertEq(governance.sharesByUser(user), 1e18 + 2e18 * WAD / governance.currentShareRate());

        // withdraw 0.5 half of shares
        vm.warp(block.timestamp + 86400 * 30);
        assertEq(governance.withdrawShares(governance.sharesByUser(user) / 2), 1.5e18);

        // withdraw remaining shares
        assertEq(governance.withdrawShares(governance.sharesByUser(user)), 1.5e18);

        vm.stopPrank();
    }

    function test_depositLQTYViaPermit() public {
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
        assertEq(governance.depositLQTYViaPermit(1e18, permitParams), 1e18);
        assertEq(governance.sharesByUser(wallet.addr), 1e18);
    }

    function test_currentShareRate() public payable {
        vm.warp(0);
        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(0),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: 0,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );
        assertEq(governance.currentShareRate(), 1e18);

        vm.warp(1);
        assertGt(governance.currentShareRate(), 1e18);

        vm.warp(365 days);
        assertEq(governance.currentShareRate(), 2 * WAD);

        vm.warp(730 days);
        assertEq(governance.currentShareRate(), 3 * WAD);

        vm.warp(1095 days);
        assertEq(governance.currentShareRate(), 4 * WAD);
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

    function test_sharesToVotes() public {
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 0);

        vm.warp(block.timestamp + 365 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 1e18);

        vm.warp(block.timestamp + 730 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 3e18);

        vm.warp(block.timestamp + 1095 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 6e18);
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
        IGovernance.Snapshot memory snapshot = IGovernance.Snapshot(1e18, 1);
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (uint240 votes,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        uint256 boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(3)), bytes32(abi.encode(boldAccrued)));
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
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: 10e18,
                minAccrual: 10e18,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF
            }),
            initialInitiatives
        );

        snapshot = IGovernance.Snapshot(10000e18, 1);
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (votes,) = governance.votesSnapshot();
        assertEq(votes, 10000e18);

        boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(3)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    function test_registerInitiative() public {
        IGovernance.Snapshot memory snapshot = IGovernance.Snapshot(1e18, 1);
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (uint240 votes,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.registerInitiative(initiative3);

        vm.startPrank(lusdHolder);
        lusd.transfer(address(this), 1e18);
        vm.stopPrank();

        lusd.approve(address(governance), 1e18);

        vm.expectRevert("Governance: insufficient-shares");
        governance.registerInitiative(initiative3);

        vm.store(address(governance), keccak256(abi.encode(address(this), 1)), bytes32(abi.encode(1e18)));
        assertEq(governance.sharesByUser(address(this)), 1e18);
        vm.warp(block.timestamp + 365 days);

        governance.registerInitiative(initiative3);
        assertEq(governance.initiativesRegistered(initiative3), block.timestamp);
    }

    function test_allocateShares() public {
        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(governance.depositLQTY(1e18), 1e18);

        assertEq(governance.qualifyingShares(), 0);
        (uint192 sharesAllocatedByUser_, uint16 atEpoch) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);
        assertEq(atEpoch, 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = 1e18;
        int256[] memory deltaVetoShares = new int256[](1);

        vm.expectRevert("Governance: initiative-not-active");
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + 365 days);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(governance.qualifyingShares(), 1e18);
        (sharesAllocatedByUser_, atEpoch) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 1e18);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        vm.expectRevert("Governance: insufficient-unallocated-shares");
        governance.withdrawShares(1e18);

        vm.warp(block.timestamp + governance.secondsUntilNextEpoch() - 1);

        initiatives[0] = initiative;
        deltaShares[0] = 1e18;
        vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        initiatives[0] = initiative;
        deltaShares[0] = -1e18;
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(governance.qualifyingShares(), 0);
        (sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);

        vm.stopPrank();
    }

    function test_claimForInitiative() public {
        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        assertEq(governance.depositLQTY(1000e18), 1000e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(governance.qualifyingShares(), 0);
        (uint192 sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](2);
        initiatives[0] = initiative;
        initiatives[1] = initiative2;
        int256[] memory deltaShares = new int256[](2);
        deltaShares[0] = 500e18;
        deltaShares[1] = 500e18;
        int256[] memory deltaVetoShares = new int256[](2);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);
        assertEq(governance.qualifyingShares(), 1000e18);
        (sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(initiative), 5000e18);
        assertEq(governance.claimForInitiative(initiative), 0);

        assertEq(lusd.balanceOf(initiative), 5000e18);

        assertEq(governance.claimForInitiative(initiative2), 5000e18);
        assertEq(governance.claimForInitiative(initiative2), 0);

        assertEq(lusd.balanceOf(initiative2), 5000e18);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiatives[0] = initiative;
        initiatives[1] = initiative2;
        deltaShares[0] = 495e18;
        deltaShares[1] = -495e18;
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(initiative), 10000e18);
        assertEq(governance.claimForInitiative(initiative), 0);
        
        assertEq(lusd.balanceOf(initiative), 15000e18);

        assertEq(governance.claimForInitiative(initiative2), 0);
        assertEq(governance.claimForInitiative(initiative2), 0);

        assertEq(lusd.balanceOf(initiative2), 5000e18);

        vm.stopPrank();
    }

    function test_multicall() public {
        vm.startPrank(user);

        vm.warp(block.timestamp + 365 days);

        uint256 lqtyAmount = 1000e18;
        uint256 shareAmount = lqtyAmount * WAD / governance.currentShareRate();
        uint256 lqtyBalance = lqty.balanceOf(user);

        lqty.approve(address(governance.deriveUserProxyAddress(user)), lqtyAmount);

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = int256(shareAmount);
        int256[] memory deltaVetoShares = new int256[](1);

        int256[] memory deltaShares_ = new int256[](1);
        deltaShares_[0] = -int256(shareAmount);

        bytes[] memory data = new bytes[](7);
        data[0] = abi.encodeWithSignature("deployUserProxy()");
        data[1] = abi.encodeWithSignature("depositLQTY(uint256)", lqtyAmount);
        data[2] = abi.encodeWithSignature(
            "allocateShares(address[],int256[],int256[])", initiatives, deltaShares, deltaVetoShares
        );
        data[3] = abi.encodeWithSignature("sharesAllocatedToInitiative(address)", initiative);
        data[4] = abi.encodeWithSignature("snapshotVotesForInitiative(address)", initiative);
        data[5] = abi.encodeWithSignature(
            "allocateShares(address[],int256[],int256[])", initiatives, deltaShares_, deltaVetoShares
        );
        data[6] = abi.encodeWithSignature("withdrawShares(uint256)", shareAmount);
        bytes[] memory response = governance.multicall(data);

        (IGovernance.ShareAllocation memory shareAllocation) = abi.decode(response[3], (IGovernance.ShareAllocation));
        assertEq(shareAllocation.shares, shareAmount);
        (IGovernance.Snapshot memory votes, IGovernance.Snapshot memory votesForInitiative) =
            abi.decode(response[4], (IGovernance.Snapshot, IGovernance.Snapshot));
        assertEq(votes.votes + votesForInitiative.votes, 0);
        assertEq(lqty.balanceOf(user), lqtyBalance);

        vm.stopPrank();
    }
}
