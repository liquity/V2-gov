// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {IBribeInitiative} from "./interfaces/IBribeInitiative.sol";

import {DoubleLinkedList} from "./utils/DoubleLinkedList.sol";

import {EncodingDecodingLib} from "src/utils/EncodingDecodingLib.sol";

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
    function totalLQTYAllocatedByEpoch(uint16 _epoch) external view returns (uint88, uint32) {
        return _loadTotalLQTYAllocation(_epoch);
    }

    /// @inheritdoc IBribeInitiative
    function lqtyAllocatedByUserAtEpoch(address _user, uint16 _epoch) external view returns (uint88, uint32) {
        return _loadLQTYAllocation(_user, _epoch);
    }

    /// @inheritdoc IBribeInitiative
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint16 _epoch) external {
        uint16 epoch = governance.epoch();
        require(_epoch >= epoch, "BribeInitiative: only-future-epochs");

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
        uint16 _epoch,
        uint16 _prevLQTYAllocationEpoch,
        uint16 _prevTotalLQTYAllocationEpoch
    ) internal returns (uint256 boldAmount, uint256 bribeTokenAmount) {
        require(_epoch < governance.epoch(), "BribeInitiative: cannot-claim-for-current-epoch");
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

        (uint88 totalLQTY, uint32 totalAverageTimestamp) = _decodeLQTYAllocation(totalLQTYAllocation.value);
        uint240 totalVotes = governance.lqtyToVotes(totalLQTY, block.timestamp, totalAverageTimestamp);
        if (totalVotes != 0) {
            (uint88 lqty, uint32 averageTimestamp) = _decodeLQTYAllocation(lqtyAllocation.value);
            uint240 votes = governance.lqtyToVotes(lqty, block.timestamp, averageTimestamp);
            boldAmount = uint256(bribe.boldAmount) * uint256(votes) / uint256(totalVotes);
            bribeTokenAmount = uint256(bribe.bribeTokenAmount) * uint256(votes) / uint256(totalVotes);
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
    function onRegisterInitiative(uint16) external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint16) external virtual override onlyGovernance {}

    function _setTotalLQTYAllocationByEpoch(uint16 _epoch, uint88 _lqty, uint32 _averageTimestamp, bool _insert)
        private
    {
        uint224 value = (uint224(_lqty) << 32) | _averageTimestamp;
        if (_insert) {
            totalLQTYAllocationByEpoch.insert(_epoch, value, 0);
        } else {
            totalLQTYAllocationByEpoch.items[_epoch].value = value;
        }
        emit ModifyTotalLQTYAllocation(_epoch, _lqty, _averageTimestamp);
    }

    function _setLQTYAllocationByUserAtEpoch(
        address _user,
        uint16 _epoch,
        uint88 _lqty,
        uint32 _averageTimestamp,
        bool _insert
    ) private {
        uint224 value = (uint224(_lqty) << 32) | _averageTimestamp;
        if (_insert) {
            lqtyAllocationByUserAtEpoch[_user].insert(_epoch, value, 0);
        } else {
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].value = value;
        }
        emit ModifyLQTYAllocation(_user, _epoch, _lqty, _averageTimestamp);
    }

    function _encodeLQTYAllocation(uint88 _lqty, uint32 _averageTimestamp) private pure returns (uint224) {
        return EncodingDecodingLib.encodeLQTYAllocation(_lqty, _averageTimestamp);
    }

    function _decodeLQTYAllocation(uint224 _value) private pure returns (uint88, uint32) {
        return EncodingDecodingLib.decodeLQTYAllocation(_value);
    }

    function _loadTotalLQTYAllocation(uint16 _epoch) private view returns (uint88, uint32) {
        require(_epoch <= governance.epoch(), "No future Lookup");
        return _decodeLQTYAllocation(totalLQTYAllocationByEpoch.items[_epoch].value);
    }

    function _loadLQTYAllocation(address _user, uint16 _epoch) private view returns (uint88, uint32) {
        require(_epoch <= governance.epoch(), "No future Lookup");
        return _decodeLQTYAllocation(lqtyAllocationByUserAtEpoch[_user].items[_epoch].value);
    }

    /// @inheritdoc IBribeInitiative
    function getMostRecentUserEpoch(address _user) external view returns (uint16) {
        uint16 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();

        return mostRecentUserEpoch;
    }

    /// @inheritdoc IBribeInitiative
    function getMostRecentTotalEpoch() external view returns (uint16) {
        uint16 mostRecentTotalEpoch = totalLQTYAllocationByEpoch.getHead();

        return mostRecentTotalEpoch;
    }

    function onAfterAllocateLQTY(
        uint16 _currentEpoch,
        address _user,
        IGovernance.UserState calldata _userState,
        IGovernance.Allocation calldata _allocation,
        IGovernance.InitiativeState calldata _initiativeState
    ) external virtual onlyGovernance {
        if (_currentEpoch == 0) return;

        uint16 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();
        uint16 mostRecentTotalEpoch = totalLQTYAllocationByEpoch.getHead();

        _setTotalLQTYAllocationByEpoch(
            _currentEpoch,
            _initiativeState.voteLQTY,
            _initiativeState.averageStakingTimestampVoteLQTY,
            mostRecentTotalEpoch != _currentEpoch // Insert if current > recent
        );

        _setLQTYAllocationByUserAtEpoch(
            _user,
            _currentEpoch,
            _allocation.voteLQTY,
            _userState.averageStakingTimestamp,
            mostRecentUserEpoch != _currentEpoch // Insert if user current > recent
        );
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint16, uint256) external virtual override onlyGovernance {}
}
