// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2 as console} from "forge-std/console2.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";
import {IBribeInitiative} from "../src/interfaces/IBribeInitiative.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {MockERC20Tester} from "./mocks/MockERC20Tester.sol";
import {MockStakingV1} from "./mocks/MockStakingV1.sol";
import {MockStakingV1Deployer} from "./mocks/MockStakingV1Deployer.sol";
import {Random} from "./util/Random.sol";
import {UintArray} from "./util/UintArray.sol";
import {StringFormatting} from "./util/StringFormatting.sol";

contract BribeInitiativeFireAndForgetTest is MockStakingV1Deployer {
    using Random for Random.Context;
    using UintArray for uint256[];
    using Strings for *;
    using StringFormatting for *;

    uint32 constant START_TIME = 1732873631;
    uint32 constant EPOCH_DURATION = 7 days;
    uint32 constant EPOCH_VOTING_CUTOFF = 6 days;

    uint256 constant MAX_NUM_EPOCHS = 100;
    uint256 constant MAX_VOTE = 1e6 ether;
    uint128 constant MAX_BRIBE = 1e6 ether;
    uint256 constant MAX_CLAIMS_PER_CALL = 10;
    uint256 constant MEAN_TIME_BETWEEN_VOTES = 2 * EPOCH_DURATION;
    uint256 constant VOTER_PROBABILITY = type(uint256).max / 10;

    address constant voter = address(uint160(uint256(keccak256("voter"))));
    address constant other = address(uint160(uint256(keccak256("other"))));
    address constant briber = address(uint160(uint256(keccak256("briber"))));

    IGovernance.Configuration config = IGovernance.Configuration({
        registrationFee: 0,
        registrationThresholdFactor: 0,
        unregistrationThresholdFactor: 4 ether,
        unregistrationAfterEpochs: 4,
        votingThresholdFactor: 1e4, // min value that doesn't result in division by zero
        minClaim: 0,
        minAccrual: 0,
        epochStart: START_TIME - EPOCH_DURATION,
        epochDuration: EPOCH_DURATION,
        epochVotingCutoff: EPOCH_VOTING_CUTOFF
    });

    struct Vote {
        uint256 epoch;
        uint256 amount;
    }

    MockStakingV1 stakingV1;
    MockERC20Tester lqty;
    MockERC20Tester lusd;
    MockERC20Tester bold;
    MockERC20Tester bryb;
    Governance governance;
    BribeInitiative bribeInitiative;

    mapping(address who => address[]) initiativesToReset;
    mapping(address who => Vote) latestVote;
    mapping(uint256 epoch => uint256) boldAtEpoch;
    mapping(uint256 epoch => uint256) brybAtEpoch;
    mapping(uint256 epoch => uint256) voteAtEpoch; // number of LQTY allocated by "voter"
    mapping(uint256 epoch => uint256) toteAtEpoch; // number of LQTY allocated in total ("voter" + "other")
    mapping(uint256 epoch => IBribeInitiative.ClaimData) claimDataAtEpoch;
    IBribeInitiative.ClaimData[] claimData;

    function setUp() external {
        vm.warp(START_TIME);

        vm.label(voter, "voter");
        vm.label(other, "other");
        vm.label(briber, "briber");

        (stakingV1, lqty, lusd) = deployMockStakingV1();

        bold = new MockERC20Tester("BOLD Stablecoin", "BOLD");
        vm.label(address(bold), "BOLD");

        bryb = new MockERC20Tester("Bribe Token", "BRYB");
        vm.label(address(bryb), "BRYB");

        governance = new Governance({
            _lqty: address(lqty),
            _lusd: address(lusd),
            _stakingV1: address(stakingV1),
            _bold: address(bold),
            _config: config,
            _owner: address(this),
            _initiatives: new address[](0)
        });

        bribeInitiative =
            new BribeInitiative({_governance: address(governance), _bold: address(bold), _bribeToken: address(bryb)});

        address[] memory initiatives = new address[](1);
        initiatives[0] = address(bribeInitiative);
        governance.registerInitialInitiatives(initiatives);

        address voterProxy = governance.deriveUserProxyAddress(voter);
        vm.label(voterProxy, "voterProxy");

        address otherProxy = governance.deriveUserProxyAddress(other);
        vm.label(otherProxy, "otherProxy");

        lqty.mint(voter, MAX_VOTE);
        lqty.mint(other, MAX_VOTE);

        vm.startPrank(voter);
        lqty.approve(voterProxy, MAX_VOTE);
        governance.depositLQTY(MAX_VOTE);
        vm.stopPrank();

        vm.startPrank(other);
        lqty.approve(otherProxy, MAX_VOTE);
        governance.depositLQTY(MAX_VOTE);
        vm.stopPrank();

        vm.startPrank(briber);
        bold.approve(address(bribeInitiative), type(uint256).max);
        bryb.approve(address(bribeInitiative), type(uint256).max);
        vm.stopPrank();
    }

    // Ridiculously slow on Github
    /// forge-config: ci.fuzz.runs = 50
    function test_AbleToClaimBribesInAnyOrder_EvenFromEpochsWhereVoterStayedInactive(bytes32 seed) external {
        Random.Context memory random = Random.init(seed);
        uint256 startingEpoch = governance.epoch();
        uint256 lastEpoch = startingEpoch;

        for (uint256 i = startingEpoch; i < startingEpoch + MAX_NUM_EPOCHS; ++i) {
            boldAtEpoch[i] = random.generate(MAX_BRIBE);
            brybAtEpoch[i] = random.generate(MAX_BRIBE);

            bold.mint(briber, boldAtEpoch[i]);
            bryb.mint(briber, brybAtEpoch[i]);

            vm.prank(briber);
            bribeInitiative.depositBribe(uint128(boldAtEpoch[i]), uint128(brybAtEpoch[i]), i);
        }

        for (;;) {
            vm.warp(block.timestamp + random.generate(2 * MEAN_TIME_BETWEEN_VOTES));
            uint256 epoch = governance.epoch();

            for (uint256 i = lastEpoch; i < epoch; ++i) {
                voteAtEpoch[i] = latestVote[voter].amount;
                toteAtEpoch[i] = latestVote[voter].amount + latestVote[other].amount;
                claimDataAtEpoch[i].epoch = i;
                claimDataAtEpoch[i].prevLQTYAllocationEpoch = latestVote[voter].epoch;
                claimDataAtEpoch[i].prevTotalLQTYAllocationEpoch =
                    uint256(Math.max(latestVote[voter].epoch, latestVote[other].epoch));

                console.log(
                    string.concat(
                        "epoch #",
                        i.toString(),
                        ": vote = ",
                        voteAtEpoch[i].decimal(),
                        ", tote = ",
                        toteAtEpoch[i].decimal()
                    )
                );
            }

            lastEpoch = epoch;
            if (epoch >= startingEpoch + MAX_NUM_EPOCHS) break;

            (IGovernance.InitiativeStatus status,,) = governance.getInitiativeState(address(bribeInitiative));

            if (status == IGovernance.InitiativeStatus.CLAIMABLE) {
                governance.claimForInitiative(address(bribeInitiative));
            }

            if (status == IGovernance.InitiativeStatus.UNREGISTERABLE) {
                governance.unregisterInitiative(address(bribeInitiative));
                break;
            }

            address who = random.generate() < VOTER_PROBABILITY ? voter : other;
            uint256 vote = governance.secondsWithinEpoch() <= EPOCH_VOTING_CUTOFF ? random.generate(MAX_VOTE) : 0;

            if (vote > 0 || latestVote[who].amount > 0) {
                // can't reset when already reset
                latestVote[who].epoch = epoch;
                latestVote[who].amount = vote;
                _vote(who, address(bribeInitiative), latestVote[who].amount);
            }
        }

        uint256[] memory epochPermutation = UintArray.seq(startingEpoch, lastEpoch + 1).permute(random);
        uint256 start = 0;
        uint256 expectedBold = 0;
        uint256 expectedBryb = 0;

        while (start < epochPermutation.length) {
            uint256 end = Math.min(start + random.generate(MAX_CLAIMS_PER_CALL), epochPermutation.length);

            for (uint256 i = start; i < end; ++i) {
                if (
                    voteAtEpoch[epochPermutation[i]] > 0
                        && (boldAtEpoch[epochPermutation[i]] > 0 || brybAtEpoch[epochPermutation[i]] > 0)
                ) {
                    claimData.push(claimDataAtEpoch[epochPermutation[i]]);
                    expectedBold += boldAtEpoch[epochPermutation[i]] * voteAtEpoch[epochPermutation[i]]
                        / toteAtEpoch[epochPermutation[i]];
                    expectedBryb += brybAtEpoch[epochPermutation[i]] * voteAtEpoch[epochPermutation[i]]
                        / toteAtEpoch[epochPermutation[i]];
                }
            }

            vm.prank(voter);
            bribeInitiative.claimBribes(claimData);
            delete claimData;

            assertEqDecimal(bold.balanceOf(voter), expectedBold, 18, "bold.balanceOf(voter) != expectedBold");
            assertEqDecimal(bryb.balanceOf(voter), expectedBryb, 18, "bryb.balanceOf(voter) != expectedBryb");

            start = end;
        }
    }

    /////////////
    // Helpers //
    /////////////

    function _vote(address who, address initiative, uint256 vote) internal {
        assertLeDecimal(vote, uint256(int256(type(int256).max)), 18, "vote > type(uint256).max");
        vm.startPrank(who);

        if (vote > 0) {
            address[] memory initiatives = new address[](1);
            int256[] memory votes = new int256[](1);
            int256[] memory vetos = new int256[](1);

            initiatives[0] = initiative;
            votes[0] = int256(uint256(vote));
            governance.allocateLQTY(initiativesToReset[who], initiatives, votes, vetos);

            if (initiativesToReset[who].length != 0) initiativesToReset[who].pop();
            initiativesToReset[who].push(initiative);
        } else {
            if (initiativesToReset[who].length != 0) {
                governance.resetAllocations(initiativesToReset[who], true);
                initiativesToReset[who].pop();
            }
        }

        vm.stopPrank();
    }
}
