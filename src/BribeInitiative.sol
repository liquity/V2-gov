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

    // bribe treasury
    address public immutable bribeTreasury;

    constructor(address _governance, address _bold, address _bribeToken) {
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        bribeToken = IERC20(_bribeToken);
        bribeTreasury = address(new BribeTreasury());
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
        bold.safeTransferFrom(msg.sender, bribeTreasury, _boldAmount);
        bribeToken.safeTransferFrom(msg.sender, bribeTreasury, _bribeTokenAmount);

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

        boldAmount = uint256(bribe.boldAmount) * uint256(lqtyAllocation.value) / uint256(totalLQTYAllocation.value);
        bribeTokenAmount =
            uint256(bribe.bribeTokenAmount) * uint256(lqtyAllocation.value) / uint256(totalLQTYAllocation.value);

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

        if (boldAmount != 0 || bribeTokenAmount != 0) {
            IBribeTreasury(bribeTreasury).claimBribes(msg.sender, bribeTokenAmount, boldAmount);
        }
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative(uint16) external virtual override onlyGovernance {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative(uint16) external virtual override onlyGovernance {}

    function _setTotalLQTYAllocationByEpoch(uint16 _epoch, uint88 _value, bool _insert) private {
        if (_insert) {
            totalLQTYAllocationByEpoch.insert(_epoch, _value, 0);
        } else {
            totalLQTYAllocationByEpoch.items[_epoch].value = _value;
        }
        emit ModifyTotalLQTYAllocation(_epoch, _value);
    }

    function _setLQTYAllocationByUserAtEpoch(address _user, uint16 _epoch, uint88 _value, bool _insert) private {
        if (_insert) {
            lqtyAllocationByUserAtEpoch[_user].insert(_epoch, _value, 0);
        } else {
            lqtyAllocationByUserAtEpoch[_user].items[_epoch].value = _value;
        }
        emit ModifyLQTYAllocation(_user, _epoch, _value);
    }

    /// @inheritdoc IInitiative
    function onAfterAllocateLQTY(uint16 _currentEpoch, address _user, uint88 _voteLQTY, uint88 _vetoLQTY)
        external
        virtual
        onlyGovernance
    {
        uint16 mostRecentUserEpoch = lqtyAllocationByUserAtEpoch[_user].getHead();

        if (_currentEpoch == 0) return;

        // if this is the first user allocation in the epoch, then insert a new item into the user allocation DLL
        if (mostRecentUserEpoch != _currentEpoch) {
            uint88 prevVoteLQTY = lqtyAllocationByUserAtEpoch[_user].items[mostRecentUserEpoch].value;
            uint88 newVoteLQTY = (_vetoLQTY == 0) ? _voteLQTY : 0;
            uint16 mostRecentTotalEpoch = totalLQTYAllocationByEpoch.getHead();
            // if this is the first allocation in the epoch, then insert a new item into the total allocation DLL
            if (mostRecentTotalEpoch != _currentEpoch) {
                uint88 prevTotalLQTYAllocation = totalLQTYAllocationByEpoch.items[mostRecentTotalEpoch].value;
                if (_vetoLQTY == 0) {
                    // no veto to no veto
                    _setTotalLQTYAllocationByEpoch(
                        _currentEpoch, prevTotalLQTYAllocation + newVoteLQTY - prevVoteLQTY, true
                    );
                } else {
                    if (prevVoteLQTY != 0) {
                        // if the prev user allocation was counted in, then remove the prev user allocation from the
                        // total allocation (no veto to veto)
                        _setTotalLQTYAllocationByEpoch(_currentEpoch, prevTotalLQTYAllocation - prevVoteLQTY, true);
                    } else {
                        // veto to veto
                        _setTotalLQTYAllocationByEpoch(_currentEpoch, prevTotalLQTYAllocation, true);
                    }
                }
            } else {
                if (_vetoLQTY == 0) {
                    // no veto to no veto
                    _setTotalLQTYAllocationByEpoch(
                        _currentEpoch,
                        totalLQTYAllocationByEpoch.items[_currentEpoch].value + newVoteLQTY - prevVoteLQTY,
                        false
                    );
                } else if (prevVoteLQTY != 0) {
                    // no veto to veto
                    _setTotalLQTYAllocationByEpoch(
                        _currentEpoch, totalLQTYAllocationByEpoch.items[_currentEpoch].value - prevVoteLQTY, false
                    );
                }
            }
            // insert a new item into the user allocation DLL
            _setLQTYAllocationByUserAtEpoch(_user, _currentEpoch, newVoteLQTY, true);
        } else {
            uint88 prevVoteLQTY = lqtyAllocationByUserAtEpoch[_user].getItem(_currentEpoch).value;
            if (_vetoLQTY == 0) {
                // update the allocation for the current epoch by adding the new allocation and subtracting
                // the previous one (no veto to no veto)
                _setTotalLQTYAllocationByEpoch(
                    _currentEpoch,
                    totalLQTYAllocationByEpoch.items[_currentEpoch].value + _voteLQTY - prevVoteLQTY,
                    false
                );
                _setLQTYAllocationByUserAtEpoch(_user, _currentEpoch, _voteLQTY, false);
            } else {
                // if the user vetoed the initiative, subtract the allocation from the DLLs (no veto to veto)
                _setTotalLQTYAllocationByEpoch(
                    _currentEpoch, totalLQTYAllocationByEpoch.items[_currentEpoch].value - prevVoteLQTY, false
                );
                _setLQTYAllocationByUserAtEpoch(_user, _currentEpoch, 0, false);
            }
        }
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint16, uint256) external virtual override onlyGovernance {}
}

interface IBribeTreasury {
    function claimBribes(address caller, uint256 bribeTokenAmt, uint256 boldAmount) external;
}

contract BribeTreasury is IBribeTreasury {
    address public immutable bribeInitiative;

    constructor() {
        bribeInitiative = msg.sender;
    }

    function claimBribes(address caller, uint256 bribeTokenAmt, uint256 boldAmount) external {
        require(msg.sender == bribeInitiative, "BribeTreasury: invalid-sender");
        IBribeInitiative(bribeInitiative).bold().transfer(caller, boldAmount);
        IBribeInitiative(bribeInitiative).bribeToken().transfer(caller, bribeTokenAmt);
    }
}
