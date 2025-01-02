// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance, UNREGISTERED_INITIATIVE} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {IBribeInitiative} from "./interfaces/IBribeInitiative.sol";

import {DoubleLinkedList} from "./utils/DoubleLinkedList.sol";
import {_lqtyToVotes} from "./utils/VotingPower.sol";

contract BribeInitiative is IInitiative, IBribeInitiative {
    using SafeERC20 for IERC20;
    using DoubleLinkedList for DoubleLinkedList.List;

    uint256 internal immutable EPOCH_START;
    uint256 internal immutable EPOCH_DURATION;

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

        EPOCH_START = governance.EPOCH_START();
        EPOCH_DURATION = governance.EPOCH_DURATION();
    }

    modifier onlyGovernance() {
        require(msg.sender == address(governance), "BribeInitiative: invalid-sender");
        _;
    }

    /// @inheritdoc IBribeInitiative
    function totalLQTYAllocatedByEpoch(uint256 _epoch) external view returns (uint256, uint256) {
        return (totalLQTYAllocationByEpoch.items[_epoch].lqty, totalLQTYAllocationByEpoch.items[_epoch].offset);
    }

    /// @inheritdoc IBribeInitiative
    function lqtyAllocatedByUserAtEpoch(address _user, uint256 _epoch) external view returns (uint256, uint256) {
        return (
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].lqty,
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].offset
        );
    }

    /// @inheritdoc IBribeInitiative
    function depositBribe(uint256 _boldAmount, uint256 _bribeTokenAmount, uint256 _epoch) external {
        uint256 epoch = governance.epoch();
        require(_epoch >= epoch, "BribeInitiative: now-or-future-epochs");

        bribeByEpoch[_epoch].remainingBoldAmount += _boldAmount;
        bribeByEpoch[_epoch].remainingBribeTokenAmount += _bribeTokenAmount;

        emit DepositBribe(msg.sender, _boldAmount, _bribeTokenAmount, _epoch);

        bold.safeTransferFrom(msg.sender, address(this), _boldAmount);
        bribeToken.safeTransferFrom(msg.sender, address(this), _bribeTokenAmount);
    }

    function _getValidatedLQTYAllocation(
        DoubleLinkedList.List storage _list,
        uint256 _epoch,
        uint256 _prevAllocationEpoch,
        string memory _errorMsg
    ) internal view returns (DoubleLinkedList.Item memory _item) {
        if (_prevAllocationEpoch == 0) {
            require(_list.isEmpty(), _errorMsg);
            // Leaving _item uninitialized, as there's never been an allocation
        } else {
            require(_list.contains(_prevAllocationEpoch), _errorMsg);
            _item = _list.getItem(_prevAllocationEpoch);
            require(_prevAllocationEpoch <= _epoch && (_item.next > _epoch || _item.next == 0), _errorMsg);
        }
    }

    // Returns true if there are no existing LQTY allocations to the initiative, and there's no possibility of
    // allocating any more because the initiative's been unregistered.
    function _noPresentOrFutureAllocation() internal view returns (bool) {
        // Note that the initiative could already be unregisterable but not yet unregistered, which we ignore here.
        // In that case, the stuck bribes can always be extracted in the next epoch _after_ unregistering the initiative.
        uint256 latestTotalAllocationEpoch = getMostRecentTotalEpoch();
        return (
            latestTotalAllocationEpoch == 0 || totalLQTYAllocationByEpoch.getItem(latestTotalAllocationEpoch).lqty == 0
        ) && governance.registeredInitiatives(address(this)) == UNREGISTERED_INITIATIVE;
    }

    /// @inheritdoc IBribeInitiative
    function redepositBribe(uint256 _originalEpoch, uint256 _prevTotalLQTYAllocationEpoch) external {
        Bribe memory bribe = bribeByEpoch[_originalEpoch];
        require(bribe.remainingBoldAmount != 0 || bribe.remainingBribeTokenAmount != 0, "BribeInitiative: no-bribe");

        DoubleLinkedList.Item memory totalLQTYAllocation = _getValidatedLQTYAllocation(
            totalLQTYAllocationByEpoch,
            _originalEpoch,
            _prevTotalLQTYAllocationEpoch,
            "BribeInitiative: invalid-prev-total-lqty-allocation-epoch"
        );

        require(totalLQTYAllocation.lqty == 0, "BribeInitiative: total-lqty-allocation-not-zero");
        assert(bribe.claimedVotes == 0); // Can't possibly have claimed anything

        if (_noPresentOrFutureAllocation()) {
            if (bribe.remainingBoldAmount != 0) {
                bold.safeTransfer(msg.sender, bribe.remainingBoldAmount);
            }
            if (bribe.remainingBribeTokenAmount != 0) {
                bribeToken.safeTransfer(msg.sender, bribe.remainingBribeTokenAmount);
            }

            emit ExtractUnclaimableBribe(
                msg.sender, _originalEpoch, bribe.remainingBoldAmount, bribe.remainingBribeTokenAmount
            );
        } else {
            uint256 currentEpoch = governance.epoch();
            bribeByEpoch[currentEpoch].remainingBoldAmount += bribe.remainingBoldAmount;
            bribeByEpoch[currentEpoch].remainingBribeTokenAmount += bribe.remainingBribeTokenAmount;

            emit RedepositBribe(
                msg.sender, bribe.remainingBoldAmount, bribe.remainingBribeTokenAmount, _originalEpoch, currentEpoch
            );
        }

        delete bribeByEpoch[_originalEpoch].remainingBoldAmount;
        delete bribeByEpoch[_originalEpoch].remainingBribeTokenAmount;
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
        require(bribe.remainingBoldAmount != 0 || bribe.remainingBribeTokenAmount != 0, "BribeInitiative: no-bribe");

        DoubleLinkedList.Item memory lqtyAllocation = _getValidatedLQTYAllocation(
            lqtyAllocationByUserAtEpoch[_user],
            _epoch,
            _prevLQTYAllocationEpoch,
            "BribeInitiative: invalid-prev-lqty-allocation-epoch"
        );
        DoubleLinkedList.Item memory totalLQTYAllocation = _getValidatedLQTYAllocation(
            totalLQTYAllocationByEpoch,
            _epoch,
            _prevTotalLQTYAllocationEpoch,
            "BribeInitiative: invalid-prev-total-lqty-allocation-epoch"
        );

        require(totalLQTYAllocation.lqty > 0, "BribeInitiative: total-lqty-allocation-zero");
        require(lqtyAllocation.lqty > 0, "BribeInitiative: lqty-allocation-zero");

        // `Governance` guarantees that `votes` evaluates to 0 or greater for each initiative at the time of allocation.
        // Since the last possible moment to allocate within this epoch is 1 second before `epochEnd`, we have that:
        //  - `lqtyAllocation.lqty > 0` implies `votes > 0`
        //  - `totalLQTYAllocation.lqty > 0` implies `totalVotes > 0`

        uint256 epochEnd = EPOCH_START + _epoch * EPOCH_DURATION;
        uint256 totalVotes = _lqtyToVotes(totalLQTYAllocation.lqty, epochEnd, totalLQTYAllocation.offset);
        uint256 votes = _lqtyToVotes(lqtyAllocation.lqty, epochEnd, lqtyAllocation.offset);
        uint256 remainingVotes = totalVotes - bribe.claimedVotes;

        boldAmount = bribe.remainingBoldAmount * votes / remainingVotes;
        bribeTokenAmount = bribe.remainingBribeTokenAmount * votes / remainingVotes;
        bribe.remainingBoldAmount -= boldAmount;
        bribe.remainingBribeTokenAmount -= bribeTokenAmount;
        bribe.claimedVotes += votes;

        bribeByEpoch[_epoch] = bribe;
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

        if (boldAmount != 0) bold.safeTransfer(msg.sender, boldAmount);
        if (bribeTokenAmount != 0) bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
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

    /// @inheritdoc IBribeInitiative
    function getMostRecentUserEpoch(address _user) external view returns (uint256) {
        uint256 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();

        return mostRecentUserEpoch;
    }

    /// @inheritdoc IBribeInitiative
    function getMostRecentTotalEpoch() public view returns (uint256) {
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
