// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {IBribeInitiative} from "./interfaces/IBribeInitiative.sol";

import {DoubleLinkedList} from "./utils/DoubleLinkedList.sol";

contract BribeInitiative is IInitiative, IBribeInitiative {
    using SafeERC20 for IERC20;
    using DoubleLinkedList for DoubleLinkedList.List;

    /// @inheritdoc IBribeInitiative
    IGovernance public immutable governance;
    /// @inheritdoc IBribeInitiative
    IERC20 public immutable bold;
    /// @inheritdoc IBribeInitiative
    IERC20 public immutable bribeToken;

    /// @inheritdoc IBribeInitiative
    mapping(uint16 => Bribe) public bribeByEpoch;
    /// @inheritdoc IBribeInitiative
    mapping(address => mapping(uint16 => bool)) public claimedBribeAtEpoch;

    /// Double linked list of the total LQTY allocated at a given epoch
    DoubleLinkedList.List internal totalLQTYAllocationByEpoch;
    /// Double linked list of LQTY allocated by a user at a given epoch
    mapping(address => DoubleLinkedList.List) internal lqtyAllocationByUserAtEpoch;

    constructor(address _governance, address _bold, address _bribeToken) {
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        bribeToken = IERC20(_bribeToken);
    }

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "BribeInitiative: invalid-sender");
        _;
    }

    /// @inheritdoc IBribeInitiative
    function totalLQTYAllocatedByEpoch(uint16 _epoch) external view returns (uint88) {
        return totalLQTYAllocationByEpoch.getValue(_epoch);
    }

    /// @inheritdoc IBribeInitiative
    function lqtyAllocatedByUserAtEpoch(address _user, uint16 _epoch) external view returns (uint88) {
        return lqtyAllocationByUserAtEpoch[_user].getValue(_epoch);
    }

    /// @inheritdoc IBribeInitiative
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint16 _epoch) external {
        bold.safeTransferFrom(msg.sender, address(this), _boldAmount);
        bribeToken.safeTransferFrom(msg.sender, address(this), _bribeTokenAmount);

        uint16 epoch = governance.epoch();
        require(_epoch > epoch, "BribeInitiative: only-future-epochs");

        Bribe memory bribe = bribeByEpoch[_epoch];
        bribe.boldAmount += _boldAmount;
        bribe.bribeTokenAmount += _bribeTokenAmount;
        bribeByEpoch[_epoch] = bribe;

        emit DepositBribe(msg.sender, _boldAmount, _bribeTokenAmount, _epoch);
    }

    function _claimBribe(
        address _user,
        uint16 _epoch,
        uint16 _prevLQTYAllocationEpoch,
        uint16 _prevTotalLQTYAllocationEpoch
    ) internal returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        require(_epoch != governance.epoch(), "BribeInitiative: cannot-claim-for-current-epoch");
        require(!claimedBribeAtEpoch[_user][_epoch], "BribeInitiative: already-claimed");

        Bribe memory bribe = bribeByEpoch[_epoch];
        require(bribe.boldAmount != 0 || bribe.bribeTokenAmount != 0, "BribeInitiative: no-bribe");

        DoubleLinkedList.Item memory lqtyAllocation =
            lqtyAllocationByUserAtEpoch[_user].getItem(_prevLQTYAllocationEpoch);
        require(
            lqtyAllocation.value != 0 && _prevLQTYAllocationEpoch <= _epoch
                && (lqtyAllocation.next > _epoch || lqtyAllocation.next == 0),
            "BribeInitiative: invalid-prev-lqty-allocation-epoch"
        );
        DoubleLinkedList.Item memory totalLQTYAllocation =
            totalLQTYAllocationByEpoch.getItem(_prevTotalLQTYAllocationEpoch);
        require(
            totalLQTYAllocation.value != 0 && _prevTotalLQTYAllocationEpoch <= _epoch
                && (totalLQTYAllocation.next > _epoch || totalLQTYAllocation.next == 0),
            "BribeInitiative: invalid-prev-total-lqty-allocation-epoch"
        );

        boldAmount = bribe.boldAmount * lqtyAllocation.value / totalLQTYAllocation.value;
        bribeTokenAmount = bribe.bribeTokenAmount * lqtyAllocation.value / totalLQTYAllocation.value;

        claimedBribeAtEpoch[_user][_epoch] = true;

        emit ClaimBribe(_user, _epoch, boldAmount, bribeTokenAmount);
    }

    /// @inheritdoc IBribeInitiative
    function claimBribes(address _user, ClaimData[] calldata _claimData)
        external
        returns (uint256 boldAmount, uint256 bribeTokenAmount)
    {
        for (uint256 i = 0; i < _claimData.length; i++) {
            ClaimData memory claimData = _claimData[i];
            (uint256 boldAmount_, uint256 bribeTokenAmount_) = _claimBribe(
                _user, claimData.epoch, claimData.prevLQTYAllocationEpoch, claimData.prevTotalLQTYAllocationEpoch
            );
            boldAmount += boldAmount_;
            bribeTokenAmount += bribeTokenAmount_;
        }

        if (boldAmount != 0) bold.safeTransfer(msg.sender, boldAmount);
        if (bribeTokenAmount != 0) bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative() external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative() external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onAfterAllocateLQTY(address _user, uint88 _voteLQTY, uint88 _vetoLQTY) external virtual onlyGovernance {
        uint16 currentEpoch = governance.epoch();
        Bribe memory bribe = bribeByEpoch[currentEpoch];
        uint256 mostRecentEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();

        if (bribe.boldAmount != 0 || bribe.bribeTokenAmount != 0 || mostRecentEpoch == 0) {
            if (mostRecentEpoch != currentEpoch && _vetoLQTY == 0) {
                uint16 mostRecentEpoch_ = totalLQTYAllocationByEpoch.getHead();
                if (mostRecentEpoch_ != currentEpoch) {
                    totalLQTYAllocationByEpoch.insert(currentEpoch, _voteLQTY, 0);
                } else {
                    totalLQTYAllocationByEpoch.items[currentEpoch].value += _voteLQTY;
                }
                lqtyAllocationByUserAtEpoch[_user].insert(currentEpoch, _voteLQTY, 0);
            } else {
                DoubleLinkedList.Item memory lqtyAllocation = lqtyAllocationByUserAtEpoch[_user].getItem(currentEpoch);
                if (_vetoLQTY == 0) {
                    totalLQTYAllocationByEpoch.items[currentEpoch].value =
                        totalLQTYAllocationByEpoch.items[currentEpoch].value + _voteLQTY - lqtyAllocation.value;
                    lqtyAllocationByUserAtEpoch[_user].items[currentEpoch].value = _voteLQTY;
                } else {
                    totalLQTYAllocationByEpoch.items[currentEpoch].value -= lqtyAllocation.value;
                    lqtyAllocationByUserAtEpoch[_user].remove(currentEpoch);
                }
            }
        }
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint256) external virtual override onlyGovernance {}
}
