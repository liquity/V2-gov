// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IDistributionCreator} from "./interfaces/IDistributionCreator.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

contract UniV4MerklRewards is IInitiative {
    using SafeERC20 for IERC20;

    address public constant LIQUITY_FUNDS_SAFE = address(0xF06016D822943C42e3Cb7FC3a6A3B1889C1045f8); // to blacklist

    uint32 public constant CAMPAIGN_TYPE = 13; // UNISWAP_V4
    IDistributionCreator constant merklDistributionCreator =
        IDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);

    IGovernance public immutable governance;
    IERC20 public immutable boldToken;

    uint256 public immutable CAMPAIGN_BOLD_AMOUNT_THRESHOLD;
    bool constant IS_OUT_OF_RANGE_INCENTIVIZED = false;
    bytes32 public immutable UNIV4_POOL_ID;
    uint32 public immutable WEIGHT_FEES; // With 2 decimals
    uint32 public immutable WEIGHT_TOKEN_0;
    uint32 public immutable WEIGHT_TOKEN_1;

    uint256 internal immutable EPOCH_START;
    uint256 internal immutable EPOCH_DURATION;

    event NewMerklCampaign(uint256 indexed claimEpoch, uint256 boldAmount, bytes32 campaingId);

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "UniV4MerklInitiative: invalid-sender");
        _;
    }

    constructor(
        address _governanceAddress,
        address _boldTokenAddress,
        uint256 _campaignBoldAmountThreshold,
        bytes32 _uniV4PoolId,
        uint32 _weightFees,
        uint32 _weightToken0,
        uint32 _weightToken1
    ) {
        require(_weightFees + _weightToken0 + _weightToken1 == 10000, "Wrong weigths");

        governance = IGovernance(_governanceAddress);
        boldToken = IERC20(_boldTokenAddress);

        CAMPAIGN_BOLD_AMOUNT_THRESHOLD = _campaignBoldAmountThreshold;
        UNIV4_POOL_ID = _uniV4PoolId;
        WEIGHT_FEES = _weightFees;
        WEIGHT_TOKEN_0 = _weightToken0;
        WEIGHT_TOKEN_1 = _weightToken1;

        EPOCH_START = governance.EPOCH_START();
        EPOCH_DURATION = governance.EPOCH_DURATION();

        // Approve BOLD to Merkl
        boldToken.approve(address(merklDistributionCreator), type(uint256).max);

        // whitelist ourselves to be able to create campaigs without signature
        merklDistributionCreator.acceptConditions();
    }

    function getCampaignData() public view returns (bytes memory) {
        return bytes.concat(
            abi.encode(
                416, // 13 * 32, offset for poolId bytes
                IS_OUT_OF_RANGE_INCENTIVIZED,
                WEIGHT_FEES,
                WEIGHT_TOKEN_0,
                WEIGHT_TOKEN_1,
                480, // 15 * 32, offset for whitelist address
                512, // 16 * 32, offset for blacklist address
                576 // 18 * 32, offset for hooks
            ),
            abi.encode(
                0, // lowerPriceTolerance
                0, // upperPriceTolerance
                0, // lowerPriceBound
                0, // upperPriceBound
                608, // 19 * 32, offset for empty unknown last param
                32, // poolId len as bytes
                UNIV4_POOL_ID,
                0, // empty whitelist
                1, // blacklist len
                LIQUITY_FUNDS_SAFE, // blacklisted address
                0, // empty hooks
                0 // empty last unknown param
            )
        );
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
    function onClaimForInitiative(uint256 _claimEpoch, uint256 _bold) external override onlyGovernance {}

    function createCampaign(uint256 _amount) internal {
        // Avoid if rewards too low
        if (_amount < CAMPAIGN_BOLD_AMOUNT_THRESHOLD) return;

        uint256 claimEpoch = governance.epoch() - 1;

        // (Only once per epoch)
        uint256 epochEnd = EPOCH_START + claimEpoch * EPOCH_DURATION;
        IDistributionCreator.CampaignParameters memory params = IDistributionCreator.CampaignParameters({
            campaignId: bytes32(0),
            creator: address(this),
            rewardToken: address(boldToken),
            amount: _amount,
            campaignType: CAMPAIGN_TYPE,
            startTimestamp: uint32(epochEnd),
            duration: uint32(EPOCH_DURATION),
            campaignData: getCampaignData()
        });
        //params.campaignId = merklDistributionCreator.campaignId(params);
        bytes32 campaignId = merklDistributionCreator.createCampaign(params);

        emit NewMerklCampaign(claimEpoch, _amount, campaignId);
    }

    // Wrapper to avoid gas limitation
    function claimForInitiative() external {
        uint256 claimableAmount = governance.claimForInitiative(address(this));
        uint256 amount = boldToken.balanceOf(address(this));
        assert(amount >= claimableAmount);
        require(amount > 0, "UniV4MerklInitiative: no funds for campaign");

        createCampaign(amount);
    }
}
