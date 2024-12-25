// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    mapping(uint256 => Bribe) public bribeByEpoch;
    /// @inheritdoc IBribeInitiative
    mapping(address => mapping(uint256 => bool)) public claimedBribeAtEpoch;

    /// Double linked list of the total LQTY allocated at a given epoch
    DoubleLinkedList.List internal totalLQTYAllocationByEpoch;
    /// Double linked list of LQTY allocated by a user at a given epoch
    mapping(address => DoubleLinkedList.List) internal lqtyAllocationByUserAtEpoch;

    constructor(address _governance, address _bold, address _bribeToken) {
        require(_bribeToken != _bold, "BribeInitiative: bribe-token-cannot-be-bold");

        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        bribeToken = IERC20(_bribeToken);
    }

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "BribeInitiative: invalid-sender");
        _;
    }

    /// @inheritdoc IBribeInitiative
    function totalLQTYAllocatedByEpoch(uint256 _epoch) external view returns (uint256, uint256) {
        return _loadTotalLQTYAllocation(_epoch);
    }

    /// @inheritdoc IBribeInitiative
    function lqtyAllocatedByUserAtEpoch(address _user, uint256 _epoch) external view returns (uint256, uint256) {
        return _loadLQTYAllocation(_user, _epoch);
    }

    /// @inheritdoc IBribeInitiative
    function depositBribe(uint256 _boldAmount, uint256 _bribeTokenAmount, uint256 _epoch) external {
        uint256 epoch = governance.epoch();
        require(_epoch >= epoch, "BribeInitiative: now-or-future-epochs");

        Bribe memory bribe = bribeByEpoch[_epoch];
        bribe.boldAmount += _boldAmount;
        bribe.bribeTokenAmount += _bribeTokenAmount;
        bribeByEpoch[_epoch] = bribe;

        emit DepositBribe(msg.sender, _boldAmount, _bribeTokenAmount, _epoch);

        bold.safeTransferFrom(msg.sender, address(this), _boldAmount);
        bribeToken.safeTransferFrom(msg.sender, address(this), _bribeTokenAmount);
    }

    function _claimBribe(
        address _user,
        uint256 _epoch,
        uint256 _prevLQTYAllocationEpoch,
        uint256 _prevTotalLQTYAllocationEpoch
    ) internal returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        require(_epoch < governance.epoch(), "BribeInitiative: cannot-claim-for-current-epoch");
        require(!claimedBribeAtEpoch[_user][_epoch], "BribeInitiative: already-claimed");

        Bribe memory bribe = bribeByEpoch[_epoch];
        require(bribe.boldAmount != 0 || bribe.bribeTokenAmount != 0, "BribeInitiative: no-bribe");

        DoubleLinkedList.Item memory lqtyAllocation =
            lqtyAllocationByUserAtEpoch[_user].getItem(_prevLQTYAllocationEpoch);

        require(
            _prevLQTYAllocationEpoch <= _epoch && (lqtyAllocation.next > _epoch || lqtyAllocation.next == 0),
            "BribeInitiative: invalid-prev-lqty-allocation-epoch"
        );
        DoubleLinkedList.Item memory totalLQTYAllocation =
            totalLQTYAllocationByEpoch.getItem(_prevTotalLQTYAllocationEpoch);
        require(
            _prevTotalLQTYAllocationEpoch <= _epoch
                && (totalLQTYAllocation.next > _epoch || totalLQTYAllocation.next == 0),
            "BribeInitiative: invalid-prev-total-lqty-allocation-epoch"
        );

        require(totalLQTYAllocation.lqty > 0, "BribeInitiative: total-lqty-allocation-zero");

        uint256 epochEnd = governance.EPOCH_START() + _epoch * governance.EPOCH_DURATION();

        uint256 totalVotes = governance.lqtyToVotes(totalLQTYAllocation.lqty, epochEnd, totalLQTYAllocation.offset);
        if (totalVotes != 0) {
            require(lqtyAllocation.lqty > 0, "BribeInitiative: lqty-allocation-zero");

            uint256 votes = governance.lqtyToVotes(lqtyAllocation.lqty, epochEnd, lqtyAllocation.offset);
            boldAmount = bribe.boldAmount * votes / totalVotes;
            bribeTokenAmount = bribe.bribeTokenAmount * votes / totalVotes;
        }

        claimedBribeAtEpoch[_user][_epoch] = true;

        emit ClaimBribe(_user, _epoch, boldAmount, bribeTokenAmount);
    }

    /// @inheritdoc IBribeInitiative
    function claimBribes(ClaimData[] calldata _claimData)
        external
        returns (uint256 boldAmount, uint256 bribeTokenAmount)
    {
        for (uint256 i = 0; i < _claimData.length; i++) {
            ClaimData memory claimData = _claimData[i];
            (uint256 boldAmount_, uint256 bribeTokenAmount_) = _claimBribe(
                msg.sender, claimData.epoch, claimData.prevLQTYAllocationEpoch, claimData.prevTotalLQTYAllocationEpoch
            );
            boldAmount += boldAmount_;
            bribeTokenAmount += bribeTokenAmount_;
        }

        // NOTE: Due to rounding errors, bribes may slightly overpay compared to what they have allocated
        // We cap to the available amount for this reason
        if (boldAmount != 0) {
            uint256 max = bold.balanceOf(address(this));
            if (boldAmount > max) {
                boldAmount = max;
            }
            bold.safeTransfer(msg.sender, boldAmount);
        }

        if (bribeTokenAmount != 0) {
            uint256 max = bribeToken.balanceOf(address(this));
            if (bribeTokenAmount > max) {
                bribeTokenAmount = max;
            }
            bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
        }
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative(uint256) external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint256) external virtual override onlyGovernance {}

    function _setTotalLQTYAllocationByEpoch(uint256 _epoch, uint256 _lqty, uint256 _offset, bool _insert) private {
        if (_insert) {
            totalLQTYAllocationByEpoch.insert(_epoch, _lqty, _offset, 0);
        } else {
            totalLQTYAllocationByEpoch.items[_epoch].lqty = _lqty;
            totalLQTYAllocationByEpoch.items[_epoch].offset = _offset;
        }
        emit ModifyTotalLQTYAllocation(_epoch, _lqty, _offset);
    }

    function _setLQTYAllocationByUserAtEpoch(
        address _user,
        uint256 _epoch,
        uint256 _lqty,
        uint256 _offset,
        bool _insert
    ) private {
        if (_insert) {
            lqtyAllocationByUserAtEpoch[_user].insert(_epoch, _lqty, _offset, 0);
        } else {
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].lqty = _lqty;
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].offset = _offset;
        }
        emit ModifyLQTYAllocation(_user, _epoch, _lqty, _offset);
    }

    function _loadTotalLQTYAllocation(uint256 _epoch) private view returns (uint256, uint256) {
        require(_epoch <= governance.epoch(), "No future Lookup");
        DoubleLinkedList.Item memory totalLqtyAllocation = totalLQTYAllocationByEpoch.items[_epoch];

        return (totalLqtyAllocation.lqty, totalLqtyAllocation.offset);
    }

    function _loadLQTYAllocation(address _user, uint256 _epoch) private view returns (uint256, uint256) {
        require(_epoch <= governance.epoch(), "No future Lookup");
        DoubleLinkedList.Item memory lqtyAllocation = lqtyAllocationByUserAtEpoch[_user].items[_epoch];

        return (lqtyAllocation.lqty, lqtyAllocation.offset);
    }

    /// @inheritdoc IBribeInitiative
    function getMostRecentUserEpoch(address _user) external view returns (uint256) {
        uint256 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();

        return mostRecentUserEpoch;
    }

    /// @inheritdoc IBribeInitiative
    function getMostRecentTotalEpoch() external view returns (uint256) {
        uint256 mostRecentTotalEpoch = totalLQTYAllocationByEpoch.getHead();

        return mostRecentTotalEpoch;
    }

    function onAfterAllocateLQTY(
        uint256 _currentEpoch,
        address _user,
        IGovernance.UserState calldata,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external virtual onlyGovernance {
        uint256 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();
        uint256 mostRecentTotalEpoch = totalLQTYAllocationByEpoch.getHead();

        _setTotalLQTYAllocationByEpoch(
            _currentEpoch,
            _initiativeState.voteLQTY,
            _initiativeState.voteOffset,
            mostRecentTotalEpoch != _currentEpoch // Insert if current > recent
        );

        _setLQTYAllocationByUserAtEpoch(
            _user,
            _currentEpoch,
            _allocation.voteLQTY,
            _allocation.voteOffset,
            mostRecentUserEpoch != _currentEpoch // Insert if user current > recent
        );
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint256, uint256) external virtual override onlyGovernance {}
}
