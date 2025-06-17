// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IDistributionCreator} from "./interfaces/IDistributionCreator.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

contract UniV4MerklRewards is IInitiative {
    using SafeERC20 for IERC20;

    uint32 constant CAMPAIGN_TYPE = 2; // TODO!!
    IDistributionCreator constant merklDistributionCreator = IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);

    IGovernance public immutable governance;
    IERC20 public immutable boldToken;

    uint256 public immutable CAMPAIGN_BOLD_AMOUNT_THRESHOLD;
    address public immutable UNIV4_POOL_ADDRESS;

    uint256 internal immutable EPOCH_START;
    uint256 internal immutable EPOCH_DURATION;

    event NewCampaign(uint256 indexed claimEpoch, uint256 boldAmount, bytes32 campaingId);

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "UniV4MerklInitiative: invalid-sender");
        _;
    }

    constructor(address _governanceAddress, address _boldTokenAddress, uint256 _campaignBoldAmountThreshold, address _uniV4PoolAddress) {
        governance = IGovernance(_governanceAddress);
        boldToken = IERC20(_boldTokenAddress);

        CAMPAIGN_BOLD_AMOUNT_THRESHOLD = _campaignBoldAmountThreshold;
        UNIV4_POOL_ADDRESS = _uniV4PoolAddress;

        EPOCH_START = governance.EPOCH_START();
        EPOCH_DURATION = governance.EPOCH_DURATION();

        // Approve BOLD to Merkl
        boldToken.approve(address(merklDistributionCreator), type(uint256).max);
    }

    function onRegisterInitiative(uint256 _atEpoch) external override {}

    /// @notice Callback hook that is called by Governance after the initiative was unregistered
    /// @param _atEpoch Epoch at which the initiative is unregistered
    function onUnregisterInitiative(uint256 _atEpoch) external override {}

    /// @notice Callback hook that is called by Governance after the LQTY allocation is updated by a user
    /// @param _currentEpoch Epoch at which the LQTY allocation is updated
    /// @param _user Address of the user that updated their LQTY allocation
    /// @param _userState User state
    /// @param _allocation Allocation state from user to initiative
    /// @param _initiativeState Initiative state
    function onAfterAllocateLQTY(
        uint256 _currentEpoch,
        address _user,
        IGovernance.UserState calldata _userState,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external override {}

    /// @notice Callback hook that is called by Governance after the claim for the last epoch was distributed
    /// to the initiative
    /// @param _claimEpoch Epoch at which the claim was distributed
    /// @param _bold Amount of BOLD that was distributed
    function onClaimForInitiative(uint256 _claimEpoch, uint256 _bold) external override onlyGovernance {
        uint256 amount = boldToken.balanceOf(address(this));
        assert(amount >= _bold);

        // Avoid if rewards too low
        if (amount < CAMPAIGN_BOLD_AMOUNT_THRESHOLD) { return; }

        // Accept conditions
        merklDistributionCreator.acceptConditions();

        // (Only once per epoch)
        uint256 epochEnd = EPOCH_START + _claimEpoch * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory params = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(this),
            rewardToken: address(boldToken),
            amount: amount,
            campaignType: CAMPAIGN_TYPE,
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: new bytes(0) // TODO
        });
        //params.campaignId = merklDistributionCreator.campaignId(params);
        bytes32 campaignId = merklDistributionCreator.createCampaign(params);

        emit NewCampaign(_claimEpoch, _bold, campaignId);
    }
}
