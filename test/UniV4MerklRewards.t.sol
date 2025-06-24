// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

import {UniV4MerklRewards, IDistributionCreator} from "../src/UniV4MerklRewards.sol";
import {Governance} from "../src/Governance.sol";

contract UniV4MerklE2ETests is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    IERC20 private constant boldToken = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
    // TODO
    address constant GOVERNANCE_WHALE = 0xF30da4E4e7e20Dbf5fBE9adCD8699075D62C60A4;
    address public LQTY_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    Governance private constant governance = Governance(0x807DEf5E7d057DF05C796F4bc75C3Fe82Bd6EeE1);
    IDistributionCreator constant merklDistributionCreator =
        IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    bytes32 private constant UNIV4_POOL_ID = 0x5d0ed52610c76d7bf729130ce7ddc0488b2f4bd0a0db1f12adbe6a32deaff893;
    uint32 private constant WEIGHT_FEES = 1500;
    uint32 private constant WEIGHT_TOKEN_0 = 4500;
    uint32 private constant WEIGHT_TOKEN_1 = 4000;

    uint256 private REGISTRATION_FEE;
    uint256 private EPOCH_START;
    uint256 private EPOCH_DURATION;

    uint256 private constant CAMPAIGN_BOLD_AMOUNT_THRESHOLD = 100e18;

    UniV4MerklRewards private uniV4MerklRewardsInitiative;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22737591);

        REGISTRATION_FEE = governance.REGISTRATION_FEE();
        EPOCH_START = governance.EPOCH_START();
        EPOCH_DURATION = governance.EPOCH_DURATION();

        uniV4MerklRewardsInitiative = new UniV4MerklRewards(
            address(governance),
            address(boldToken),
            CAMPAIGN_BOLD_AMOUNT_THRESHOLD,
            UNIV4_POOL_ID,
            WEIGHT_FEES,
            WEIGHT_TOKEN_0,
            WEIGHT_TOKEN_1
        );

        //console2.logBytes(uniV4MerklRewardsInitiative.getCampaignData());

        // Register initiative
        vm.startPrank(GOVERNANCE_WHALE);
        deal(address(boldToken), GOVERNANCE_WHALE, REGISTRATION_FEE);
        boldToken.approve(address(governance), REGISTRATION_FEE);
        governance.registerInitiative(address(uniV4MerklRewardsInitiative));
        vm.stopPrank();

        assertGt(
            governance.registeredInitiatives(address(uniV4MerklRewardsInitiative)), 0, "Initiative should be registered"
        );

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION);
    }

    function testOnlyGovernanceCanCall() external {
        uint256 epoch = governance.epoch();
        vm.expectRevert("UniV4MerklInitiative: invalid-sender");
        uniV4MerklRewardsInitiative.onClaimForInitiative(epoch, CAMPAIGN_BOLD_AMOUNT_THRESHOLD);
    }

    function testOnClaimDoesNothingIfRewardsTooLow() external {
        governance.claimForInitiative(address(uniV4MerklRewardsInitiative));

        assertEq(
            boldToken.balanceOf(address(merklDistributionCreator.distributor())),
            0,
            "Merkl Distributor should not have any BOLD"
        );
    }

    function testClaimCreatesCampaign() external {
        vm.startPrank(LQTY_WHALE);
        uint256 lqtyAmount = lqty.balanceOf(LQTY_WHALE);
        //console2.log(lqtyAmount, "lqtyAmount");
        _deposit(lqtyAmount);

        _allocate(address(uniV4MerklRewardsInitiative), lqtyAmount, 0);
        vm.stopPrank();

        // Gain some voting power
        vm.warp(block.timestamp + 30 days);

        ( /*Governance.InitiativeStatus status, uint256 lastClaimEpoch*/ ,, uint256 claimableAmount) =
            governance.getInitiativeState(address(uniV4MerklRewardsInitiative));

        uniV4MerklRewardsInitiative.claimForInitiative();

        uint256 epochEnd = EPOCH_START + (governance.epoch() - 1) * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory params = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(uniV4MerklRewardsInitiative),
            rewardToken: address(boldToken),
            amount: claimableAmount,
            campaignType: uniV4MerklRewardsInitiative.CAMPAIGN_TYPE(),
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: uniV4MerklRewardsInitiative.getCampaignData()
        });
        bytes32 campaignId = merklDistributionCreator.campaignId(params);
        IDistributionCreator.CampaignParameters memory campaign = merklDistributionCreator.campaign(campaignId);
        assertEq(campaign.creator, params.creator, "creator");
        assertEq(campaign.rewardToken, params.rewardToken, "rewardToken");
        assertEq(campaign.amount, params.amount * 97 / 100, "amount minus fees");
        assertEq(campaign.campaignType, params.campaignType, "campaignType");
        assertEq(campaign.startTimestamp, params.startTimestamp, "startTimestamp");
        assertEq(campaign.duration, params.duration, "duration");
        assertEq(campaign.campaignData, params.campaignData, "campaignData");

        assertGt(
            boldToken.balanceOf(address(merklDistributionCreator.distributor())),
            0,
            "Merkl Distributor should have some BOLD"
        );
    }

    function testClaimDoesNotCreatesAnotherCampaignIfCalledTwiceInAnEpoch() external {
        vm.startPrank(LQTY_WHALE);
        uint256 lqtyAmount = lqty.balanceOf(LQTY_WHALE);
        //console2.log(lqtyAmount, "lqtyAmount");
        _deposit(lqtyAmount);

        _allocate(address(uniV4MerklRewardsInitiative), lqtyAmount, 0);
        vm.stopPrank();

        // Gain some voting power
        vm.warp(block.timestamp + 30 days);

        ( /*Governance.InitiativeStatus status, uint256 lastClaimEpoch*/ ,, uint256 claimableAmount) =
            governance.getInitiativeState(address(uniV4MerklRewardsInitiative));

        uniV4MerklRewardsInitiative.claimForInitiative();

        uint256 epochEnd = EPOCH_START + (governance.epoch() - 1) * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory params = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(uniV4MerklRewardsInitiative),
            rewardToken: address(boldToken),
            amount: claimableAmount,
            campaignType: uniV4MerklRewardsInitiative.CAMPAIGN_TYPE(),
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: uniV4MerklRewardsInitiative.getCampaignData()
        });
        bytes32 campaignId = merklDistributionCreator.campaignId(params);
        IDistributionCreator.CampaignParameters memory campaign = merklDistributionCreator.campaign(campaignId);
        assertEq(campaign.creator, params.creator, "creator");
        assertEq(campaign.rewardToken, params.rewardToken, "rewardToken");
        assertEq(campaign.amount, params.amount * 97 / 100, "amount minus fees");
        assertEq(campaign.campaignType, params.campaignType, "campaignType");
        assertEq(campaign.startTimestamp, params.startTimestamp, "startTimestamp");
        assertEq(campaign.duration, params.duration, "duration");
        assertEq(campaign.campaignData, params.campaignData, "campaignData");

        assertGt(
            boldToken.balanceOf(address(merklDistributionCreator.distributor())),
            0,
            "Merkl Distributor should have some BOLD"
        );
        // Try to call again, without success
        vm.expectRevert("UniV4MerklInitiative: no funds for campaign");
        uniV4MerklRewardsInitiative.claimForInitiative();
    }

    function testClaimWorksEvenIfClaimedWasAlreadyDone() external {
        vm.startPrank(LQTY_WHALE);
        uint256 lqtyAmount = lqty.balanceOf(LQTY_WHALE);
        //console2.log(lqtyAmount, "lqtyAmount");
        _deposit(lqtyAmount);

        _allocate(address(uniV4MerklRewardsInitiative), lqtyAmount, 0);
        vm.stopPrank();

        // Gain some voting power
        vm.warp(block.timestamp + 30 days);

        ( /*Governance.InitiativeStatus status, uint256 lastClaimEpoch*/ ,, uint256 claimableAmount) =
            governance.getInitiativeState(address(uniV4MerklRewardsInitiative));

        uint256 epochEnd = EPOCH_START + (governance.epoch() - 1) * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory params = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(uniV4MerklRewardsInitiative),
            rewardToken: address(boldToken),
            amount: claimableAmount,
            campaignType: uniV4MerklRewardsInitiative.CAMPAIGN_TYPE(),
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: uniV4MerklRewardsInitiative.getCampaignData()
        });
        bytes32 campaignId = merklDistributionCreator.campaignId(params);

        governance.claimForInitiative(address(uniV4MerklRewardsInitiative));
        // Check campaign is not created yet
        vm.expectRevert();
        merklDistributionCreator.campaignLookup(campaignId);

        uniV4MerklRewardsInitiative.claimForInitiative();
        assertGt(merklDistributionCreator.campaignLookup(campaignId), 0, "Campaign should have been created");

        IDistributionCreator.CampaignParameters memory campaign = merklDistributionCreator.campaign(campaignId);
        assertEq(campaign.creator, params.creator, "creator");
        assertEq(campaign.rewardToken, params.rewardToken, "rewardToken");
        assertEq(campaign.amount, params.amount * 97 / 100, "amount minus fees");
        assertEq(campaign.campaignType, params.campaignType, "campaignType");
        assertEq(campaign.startTimestamp, params.startTimestamp, "startTimestamp");
        assertEq(campaign.duration, params.duration, "duration");
        assertEq(campaign.campaignData, params.campaignData, "campaignData");

        assertGt(
            boldToken.balanceOf(address(merklDistributionCreator.distributor())),
            0,
            "Merkl Distributor should have some BOLD"
        );
    }

    function _deposit(uint256 amt) internal {
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), amt);
        governance.depositLQTY(amt);
    }

    function _allocate(address initiative, uint256 votes, uint256 vetos) internal {
        address[] memory initiativesToReset;
        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory absoluteLQTYVotes = new int256[](1);
        absoluteLQTYVotes[0] = int256(votes);
        int256[] memory absoluteLQTYVetos = new int256[](1);
        absoluteLQTYVetos[0] = int256(vetos);

        governance.allocateLQTY(initiativesToReset, initiatives, absoluteLQTYVotes, absoluteLQTYVetos);
    }

    function _allocate(address[] memory initiatives, int256[] memory votes, int256[] memory vetos) internal {
        address[] memory initiativesToReset;
        governance.allocateLQTY(initiativesToReset, initiatives, votes, vetos);
    }
}
