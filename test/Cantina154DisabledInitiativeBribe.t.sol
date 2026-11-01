// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Test.sol";

import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {IBribeInitiative} from "../src/interfaces/IBribeInitiative.sol";
import {IGovernance, UNREGISTERED_INITIATIVE} from "../src/interfaces/IGovernance.sol";

import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";

contract Cantina154DisabledInitiativeBribeTest is MockStakingV1Deployer {
    uint32 internal constant START_TIME = 1_732_873_631;
    uint32 internal constant EPOCH_DURATION = 7 days;
    uint32 internal constant EPOCH_VOTING_CUTOFF = 6 days;

    uint256 internal constant STALE_VOTE = 100 ether;
    uint256 internal constant VETO_AMOUNT = 1_000 ether;
    uint256 internal constant BOLD_BRIBE = 1_000 ether;
    uint256 internal constant TOKEN_BRIBE = 500 ether;

    address internal constant staleVoter = address(0xA11CE);
    address internal constant vetoer = address(0xB0B);
    address internal constant depositor = address(0xD3F05170);

    MockStakingV1 internal stakingV1;
    MockERC20Tester internal lqty;
    MockERC20Tester internal lusd;
    MockERC20Tester internal bold;
    MockERC20Tester internal bribeToken;
    Governance internal governance;
    BribeInitiative internal bribeInitiative;

    function setUp() public {
        vm.warp(START_TIME);

        vm.label(staleVoter, "staleVoter");
        vm.label(vetoer, "vetoer");
        vm.label(depositor, "depositor");

        (stakingV1, lqty, lusd) = deployMockStakingV1();
        bold = new MockERC20Tester("BOLD Stablecoin", "BOLD");
        bribeToken = new MockERC20Tester("Independent Bribe Token", "BRIBE");

        vm.label(address(bold), "BOLD");
        vm.label(address(bribeToken), "BRIBE");

        IGovernance.Configuration memory config = IGovernance.Configuration({
            registrationFee: 0,
            registrationThresholdFactor: 0,
            unregistrationThresholdFactor: 4 ether,
            unregistrationAfterEpochs: 4,
            votingThresholdFactor: 1e4,
            minClaim: 0,
            minAccrual: 0,
            epochStart: START_TIME - EPOCH_DURATION,
            epochDuration: EPOCH_DURATION,
            epochVotingCutoff: EPOCH_VOTING_CUTOFF
        });

        governance = new Governance({
            _lqty: address(lqty),
            _lusd: address(lusd),
            _stakingV1: address(stakingV1),
            _bold: address(bold),
            _config: config,
            _owner: address(this),
            _initiatives: new address[](0)
        });

        bribeInitiative = new BribeInitiative({
            _governance: address(governance), _bold: address(bold), _bribeToken: address(bribeToken)
        });

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);
        governance.registerInitialInitiatives(initiatives);

        _depositLQTY(staleVoter, STALE_VOTE);
        _depositLQTY(vetoer, VETO_AMOUNT);

        bold.mint(depositor, BOLD_BRIBE * 2);
        bribeToken.mint(depositor, TOKEN_BRIBE * 2);

        vm.startPrank(depositor);
        bold.approve(address(bribeInitiative), type(uint256).max);
        bribeToken.approve(address(bribeInitiative), type(uint256).max);
        vm.stopPrank();

        assertEq(governance.epoch(), 2, "fixture must start after initial-initiative warm-up");
        assertTrue(staleVoter != depositor, "claimer and depositor must be distinct");
        assertTrue(vetoer != staleVoter && vetoer != depositor, "vetoer must be distinct");
    }

    function test_Cantina154_staleVoterDrainsBribeDepositedAfterUnregistration() public {
        uint256 staleEpoch = _createStaleVoteAndUnregister();
        uint256 targetEpoch = governance.epoch() + 1;

        _depositOnDisabledInitiativeAndAssert(targetEpoch);

        console2.log("Scenario A stale allocation epoch", staleEpoch);
        console2.log("Scenario A post-unregister target epoch", targetEpoch);
        console2.log("Scenario A disabled initiative BOLD balance", bold.balanceOf(address(bribeInitiative)));
        console2.log(
            "Scenario A disabled initiative bribe-token balance", bribeToken.balanceOf(address(bribeInitiative))
        );

        vm.warp(block.timestamp + 2 * EPOCH_DURATION);
        assertGt(governance.epoch(), targetEpoch, "target epoch must be claimable");

        _claimEntireDisabledDepositWithStaleNodeAndAssert(staleEpoch, targetEpoch);
    }

    function test_Cantina154_postUnregisterDepositLocksAfterAllVotesReset() public {
        uint256 staleEpoch = _createStaleVoteAndUnregister();

        address[] memory initiativesToReset = new address[](1);
        initiativesToReset[0] = address(bribeInitiative);
        vm.prank(staleVoter);
        governance.resetAllocations(initiativesToReset, true);

        uint256 zeroEpoch = governance.epoch();
        assertEq(bribeInitiative.getMostRecentUserEpoch(staleVoter), zeroEpoch, "latest user epoch must be reset");
        assertEq(bribeInitiative.getMostRecentTotalEpoch(), zeroEpoch, "latest total epoch must be reset");
        (uint256 userLQTY,,,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(staleVoter, zeroEpoch);
        (uint256 totalLQTY,,,) = bribeInitiative.totalLQTYAllocatedByEpoch(zeroEpoch);
        assertEq(userLQTY, 0, "latest user allocation must be zero after reset");
        assertEq(totalLQTY, 0, "latest total allocation must be zero after all positive votes reset");

        uint256 targetEpoch = governance.epoch() + 1;
        _depositOnDisabledInitiativeAndAssert(targetEpoch);

        console2.log("Scenario B stale epoch before reset", staleEpoch);
        console2.log("Scenario B zero-allocation epoch", zeroEpoch);
        console2.log("Scenario B post-unregister target epoch", targetEpoch);

        vm.warp(block.timestamp + 2 * EPOCH_DURATION);
        assertGt(governance.epoch(), targetEpoch, "target epoch must be in the past");

        _assertPostResetClaimRevertsAndFundsRemainLocked(zeroEpoch, targetEpoch);
    }

    function _depositOnDisabledInitiativeAndAssert(uint256 targetEpoch) internal {
        uint256 depositorBoldBefore = bold.balanceOf(depositor);
        uint256 depositorTokenBefore = bribeToken.balanceOf(depositor);
        uint256 initiativeBoldBefore = bold.balanceOf(address(bribeInitiative));
        uint256 initiativeTokenBefore = bribeToken.balanceOf(address(bribeInitiative));

        vm.prank(depositor);
        bribeInitiative.depositBribe(BOLD_BRIBE, TOKEN_BRIBE, targetEpoch);

        assertEq(bold.balanceOf(depositor), depositorBoldBefore - BOLD_BRIBE, "depositor BOLD must leave depositor");
        assertEq(
            bribeToken.balanceOf(depositor),
            depositorTokenBefore - TOKEN_BRIBE,
            "depositor bribe token must leave depositor"
        );
        assertEq(
            bold.balanceOf(address(bribeInitiative)),
            initiativeBoldBefore + BOLD_BRIBE,
            "disabled initiative must receive BOLD"
        );
        assertEq(
            bribeToken.balanceOf(address(bribeInitiative)),
            initiativeTokenBefore + TOKEN_BRIBE,
            "disabled initiative must receive bribe token"
        );

        (uint256 remainingBold, uint256 remainingToken, uint256 claimedVotes) =
            bribeInitiative.bribeByEpoch(targetEpoch);
        assertEq(remainingBold, BOLD_BRIBE, "stored BOLD bribe mismatch after disabled deposit");
        assertEq(remainingToken, TOKEN_BRIBE, "stored token bribe mismatch after disabled deposit");
        assertEq(claimedVotes, 0, "claimed votes must start at zero");
    }

    function _claimEntireDisabledDepositWithStaleNodeAndAssert(uint256 staleEpoch, uint256 targetEpoch) internal {
        uint256 staleVoterBoldBefore = bold.balanceOf(staleVoter);
        uint256 staleVoterTokenBefore = bribeToken.balanceOf(staleVoter);

        IBribeInitiative.ClaimData[] memory claimData = new IBribeInitiative.ClaimData[](1);
        claimData[0] = IBribeInitiative.ClaimData({
            epoch: targetEpoch, prevLQTYAllocationEpoch: staleEpoch, prevTotalLQTYAllocationEpoch: staleEpoch
        });

        vm.prank(staleVoter);
        (uint256 claimedBold, uint256 claimedToken) = bribeInitiative.claimBribes(claimData);

        assertEq(claimedBold, BOLD_BRIBE, "stale voter must receive 100% of post-unregister BOLD");
        assertEq(claimedToken, TOKEN_BRIBE, "stale voter must receive 100% of post-unregister bribe token");
        assertEq(bold.balanceOf(staleVoter), staleVoterBoldBefore + BOLD_BRIBE, "stale voter BOLD balance mismatch");
        assertEq(
            bribeToken.balanceOf(staleVoter),
            staleVoterTokenBefore + TOKEN_BRIBE,
            "stale voter bribe-token balance mismatch"
        );
        assertEq(bold.balanceOf(address(bribeInitiative)), 0, "initiative BOLD must be fully drained");
        assertEq(bribeToken.balanceOf(address(bribeInitiative)), 0, "initiative bribe token must be fully drained");

        (uint256 remainingBold, uint256 remainingToken, uint256 claimedVotes) =
            bribeInitiative.bribeByEpoch(targetEpoch);
        assertEq(remainingBold, 0, "remaining BOLD must be zero after drain");
        assertEq(remainingToken, 0, "remaining bribe token must be zero after drain");
        assertGt(claimedVotes, 0, "claim must account for stale voting power");
        assertTrue(bribeInitiative.claimedBribeAtEpoch(staleVoter, targetEpoch), "stale voter must be marked claimed");

        console2.log("Scenario A claimed BOLD", claimedBold);
        console2.log("Scenario A claimed bribe token", claimedToken);
        console2.log("Scenario A final initiative BOLD balance", bold.balanceOf(address(bribeInitiative)));
        console2.log("Scenario A final initiative bribe-token balance", bribeToken.balanceOf(address(bribeInitiative)));
    }

    function _assertPostResetClaimRevertsAndFundsRemainLocked(uint256 zeroEpoch, uint256 targetEpoch) internal {
        uint256 depositorBoldAfterDeposit = bold.balanceOf(depositor);
        uint256 depositorTokenAfterDeposit = bribeToken.balanceOf(depositor);
        uint256 staleVoterBoldBefore = bold.balanceOf(staleVoter);
        uint256 staleVoterTokenBefore = bribeToken.balanceOf(staleVoter);

        IBribeInitiative.ClaimData[] memory claimData = new IBribeInitiative.ClaimData[](1);
        claimData[0] = IBribeInitiative.ClaimData({
            epoch: targetEpoch, prevLQTYAllocationEpoch: zeroEpoch, prevTotalLQTYAllocationEpoch: zeroEpoch
        });

        vm.prank(staleVoter);
        vm.expectRevert("BribeInitiative: total-lqty-allocation-zero");
        bribeInitiative.claimBribes(claimData);

        assertEq(bold.balanceOf(address(bribeInitiative)), BOLD_BRIBE, "BOLD must remain locked after revert");
        assertEq(
            bribeToken.balanceOf(address(bribeInitiative)), TOKEN_BRIBE, "bribe token must remain locked after revert"
        );
        assertEq(bold.balanceOf(depositor), depositorBoldAfterDeposit, "depositor must not be refunded BOLD");
        assertEq(
            bribeToken.balanceOf(depositor), depositorTokenAfterDeposit, "depositor must not be refunded bribe token"
        );
        assertEq(bold.balanceOf(staleVoter), staleVoterBoldBefore, "reset voter must not receive BOLD");
        assertEq(bribeToken.balanceOf(staleVoter), staleVoterTokenBefore, "reset voter must not receive bribe token");

        (uint256 remainingBold, uint256 remainingToken,) = bribeInitiative.bribeByEpoch(targetEpoch);
        assertEq(remainingBold, BOLD_BRIBE, "remaining BOLD must stay fully locked");
        assertEq(remainingToken, TOKEN_BRIBE, "remaining bribe token must stay fully locked");
        assertFalse(
            bribeInitiative.claimedBribeAtEpoch(staleVoter, targetEpoch), "reverted claim must not mark voter claimed"
        );

        console2.log("Scenario B locked BOLD", remainingBold);
        console2.log("Scenario B locked bribe token", remainingToken);
    }

    function _createStaleVoteAndUnregister() internal returns (uint256 staleEpoch) {
        staleEpoch = governance.epoch();
        _allocate(staleVoter, STALE_VOTE, 0);

        assertEq(bribeInitiative.getMostRecentUserEpoch(staleVoter), staleEpoch, "stale voter head epoch mismatch");
        assertEq(bribeInitiative.getMostRecentTotalEpoch(), staleEpoch, "total head epoch mismatch");

        (uint256 userLQTY,,,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(staleVoter, staleEpoch);
        (uint256 totalLQTY,,,) = bribeInitiative.totalLQTYAllocatedByEpoch(staleEpoch);
        assertEq(userLQTY, STALE_VOTE, "stale voter positive allocation mismatch");
        assertEq(totalLQTY, STALE_VOTE, "veto must not enter positive allocation total");

        _allocate(vetoer, 0, VETO_AMOUNT);

        (totalLQTY,,,) = bribeInitiative.totalLQTYAllocatedByEpoch(staleEpoch);
        assertEq(totalLQTY, STALE_VOTE, "veto allocation must not change BribeInitiative positive total");

        vm.warp(block.timestamp + EPOCH_DURATION);
        (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(address(bribeInitiative));
        assertEq(
            uint256(status), uint256(IGovernance.InitiativeStatus.UNREGISTERABLE), "initiative must be unregisterable"
        );

        console2.log("Unregister flow stale epoch", staleEpoch);
        console2.log("Unregister flow current epoch", governance.epoch());
        console2.log("Unregister flow state before unregister", uint256(status));

        governance.unregisterInitiative(address(bribeInitiative));

        assertEq(
            governance.registeredInitiatives(address(bribeInitiative)),
            UNREGISTERED_INITIATIVE,
            "registration mapping must contain unregistered sentinel"
        );
        (status,,) = governance.getInitiativeState(address(bribeInitiative));
        assertEq(uint256(status), uint256(IGovernance.InitiativeStatus.DISABLED), "initiative must be disabled");
        assertEq(
            bribeInitiative.getMostRecentUserEpoch(staleVoter),
            staleEpoch,
            "unregister must leave stale voter epoch unchanged"
        );
        assertEq(bribeInitiative.getMostRecentTotalEpoch(), staleEpoch, "unregister must leave total epoch unchanged");

        (userLQTY,,,) = bribeInitiative.lqtyAllocatedByUserAtEpoch(staleVoter, staleEpoch);
        (totalLQTY,,,) = bribeInitiative.totalLQTYAllocatedByEpoch(staleEpoch);
        assertEq(userLQTY, STALE_VOTE, "stale voter allocation must survive unregister");
        assertEq(totalLQTY, STALE_VOTE, "positive total allocation must survive unregister");

        console2.log("Unregister flow state after unregister", uint256(status));
        console2.log("Unregister flow stale user LQTY", userLQTY);
        console2.log("Unregister flow stale total LQTY", totalLQTY);
    }

    function _depositLQTY(address user, uint256 amount) internal {
        lqty.mint(user, amount);
        address userProxy = governance.deriveUserProxyAddress(user);

        vm.startPrank(user);
        lqty.approve(userProxy, amount);
        governance.depositLQTY(amount);
        vm.stopPrank();
    }

    function _allocate(address user, uint256 vote, uint256 veto) internal {
        address[] memory initiativesToReset = new address[](0);
        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);
        int256[] memory votes = new int256[](1);
        votes[0] = int256(vote);
        int256[] memory vetos = new int256[](1);
        vetos[0] = int256(veto);

        vm.prank(user);
        governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
    }
}
