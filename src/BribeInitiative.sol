// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// import {console} from "forge-std/console.sol";

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
    /// Double linked list of the total shares allocated at a given epoch
    DoubleLinkedList.List internal totalShareAllocationByEpoch;
    /// Double linked list of shares allocated by a user at a given epoch
    mapping(address => DoubleLinkedList.List) internal shareAllocationByUserAtEpoch;

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
    function totalSharesAllocatedByEpoch(uint16 _epoch) external view returns (uint224) {
        return totalShareAllocationByEpoch.getValue(_epoch);
    }

    /// @inheritdoc IBribeInitiative
    function sharesAllocatedByUserAtEpoch(address _user, uint16 _epoch) external view returns (uint224) {
        return shareAllocationByUserAtEpoch[_user].getValue(_epoch);
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

    /// @inheritdoc IBribeInitiative
    function claimBribes(address _user, uint16 _untilEpoch)
        external
        returns (uint256 boldAmount, uint256 bribeTokenAmount)
    {
        require(_untilEpoch != governance.epoch(), "BribeInitiative: cannot-claim-for-current-epoch");

        while (true) {
            uint16 oldestEpoch = shareAllocationByUserAtEpoch[_user].getTail();
            if (oldestEpoch == 0 || _untilEpoch < oldestEpoch) break;

            DoubleLinkedList.Item memory oldestTotalShareAllocation = totalShareAllocationByEpoch.getItem(oldestEpoch);
            DoubleLinkedList.Item memory oldestShareAllocation =
                shareAllocationByUserAtEpoch[_user].getItem(oldestEpoch);

            // claim bribes for epochs between oldest epoch and the second oldest epoch, or _untilEpoch if there's no second oldest epoch
            uint16 secondOldestEpoch = (oldestShareAllocation.next != 0) ? oldestShareAllocation.next : _untilEpoch + 1;
            for (uint16 epoch = oldestEpoch; epoch < secondOldestEpoch; epoch++) {
                // if _untilEpoch is in between oldestEpoch and secondOldestEpoch,
                if (epoch > _untilEpoch) {
                    // copy the shareAllocation over to the epoch after _untilEpoch, since the shareAllocation is removed at the end
                    shareAllocationByUserAtEpoch[_user].insert(
                        epoch, oldestShareAllocation.value, oldestShareAllocation.next
                    );
                    // and if the totalShareAllocation doesn't exist, copy it over as well
                    if (!totalShareAllocationByEpoch.contains(epoch)) {
                        totalShareAllocationByEpoch.insert(
                            epoch, oldestTotalShareAllocation.value, oldestTotalShareAllocation.next
                        );
                    }
                    break;
                }
                Bribe memory bribe = bribeByEpoch[epoch];
                if (bribe.boldAmount == 0 && bribe.bribeTokenAmount == 0) continue;

                DoubleLinkedList.Item memory totalShareAllocation = totalShareAllocationByEpoch.getItem(epoch);
                uint256 totalAllocatedShares =
                    (totalShareAllocation.next != 0) ? totalShareAllocation.value : oldestTotalShareAllocation.value;
                boldAmount += bribe.boldAmount * oldestShareAllocation.value / totalAllocatedShares;
                bribeTokenAmount += bribe.bribeTokenAmount * oldestShareAllocation.value / totalAllocatedShares;
            }

            shareAllocationByUserAtEpoch[_user].remove(oldestEpoch);
        }

        if (boldAmount != 0) bold.safeTransfer(msg.sender, boldAmount);
        if (bribeTokenAmount != 0) bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative() external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative() external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onAfterAllocateShares(address _user, uint128 _shares, uint128 _vetoShares)
        external
        virtual
        onlyGovernance
    {
        uint16 currentEpoch = governance.epoch();
        Bribe memory bribe = bribeByEpoch[currentEpoch];
        uint256 mostRecentEpoch = shareAllocationByUserAtEpoch[_user].getHead();

        if (bribe.boldAmount != 0 || bribe.bribeTokenAmount != 0 || mostRecentEpoch == 0) {
            if (mostRecentEpoch != currentEpoch && _vetoShares == 0) {
                uint16 mostRecentEpoch_ = totalShareAllocationByEpoch.getHead();
                if (mostRecentEpoch_ != currentEpoch) {
                    totalShareAllocationByEpoch.insert(currentEpoch, _shares, 0);
                } else {
                    totalShareAllocationByEpoch.items[currentEpoch].value += _shares;
                }
                shareAllocationByUserAtEpoch[_user].insert(currentEpoch, _shares, 0);
            } else {
                DoubleLinkedList.Item memory shareAllocation = shareAllocationByUserAtEpoch[_user].getItem(currentEpoch);
                if (_vetoShares == 0) {
                    totalShareAllocationByEpoch.items[currentEpoch].value =
                        totalShareAllocationByEpoch.items[currentEpoch].value + _shares - shareAllocation.value;
                    shareAllocationByUserAtEpoch[_user].items[currentEpoch].value = _shares;
                } else {
                    totalShareAllocationByEpoch.items[currentEpoch].value -= shareAllocation.value;
                    shareAllocationByUserAtEpoch[_user].remove(currentEpoch);
                }
            }
        }
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint256) external virtual override onlyGovernance {}
}
