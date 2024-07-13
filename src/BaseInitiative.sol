// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";
import {IBaseInitiative} from "./interfaces/IBaseInitiative.sol";

import {sub} from "./utils/Math.sol";

contract BaseInitiative is IInitiative, IBaseInitiative {
    using SafeERC20 for IERC20;

    /// @inheritdoc IBaseInitiative
    IGovernance public immutable governance;
    /// @inheritdoc IBaseInitiative
    IERC20 public immutable bold;
    /// @inheritdoc IBaseInitiative
    IERC20 public immutable bribeToken;

    /// @inheritdoc IBaseInitiative
    mapping(address => uint16) public allocatedAtEpoch;
    /// @inheritdoc IBaseInitiative
    mapping(uint256 => Bribe) public bribeByEpoch;

    constructor(address _governance, address _bold, address _bribeToken) {
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        bribeToken = IERC20(_bribeToken);
    }

    /// @inheritdoc IBaseInitiative
    function depositBribe(uint128 _boldAmount, uint128 _bribeTokenAmount, uint256 _epoch) external {
        bold.safeTransferFrom(msg.sender, address(this), _boldAmount);
        bribeToken.safeTransferFrom(msg.sender, address(this), _bribeTokenAmount);
        uint16 epoch = governance.epoch();
        require(_epoch >= epoch, "BaseInitiative: invalid-epoch");
        Bribe memory bribe = bribeByEpoch[_epoch];
        bribe.boldAmount += _boldAmount;
        bribe.bribeTokenAmount += _bribeTokenAmount;
        bribeByEpoch[_epoch] = bribe;
    }

    function _claimBribes(address _user, uint16 _lastEpoch, uint16 _currentEpoch, int256 _deltaShares)
        internal
        returns (uint256 boldAmount, uint256 bribeTokenAmount)
    {
        // claim accrued bribes from previous epochs
        if (_lastEpoch < _currentEpoch) {
            (uint128 totalAllocatedShares,) = governance.sharesAllocatedToInitiative(address(this));
            (uint128 sharesAllocatedByUser, uint128 vetoSharesAllocatedByUser) =
                governance.sharesAllocatedByUserToInitiative(_user, address(this));
            if (int128(totalAllocatedShares) > _deltaShares && vetoSharesAllocatedByUser == 0) {
                Bribe memory bribe = bribeByEpoch[_currentEpoch];
                boldAmount = bribe.boldAmount * sub(sharesAllocatedByUser, _deltaShares)
                    / (sub(totalAllocatedShares, _deltaShares));
                if (boldAmount != 0) {
                    bold.safeTransfer(msg.sender, boldAmount);
                }
                bribeTokenAmount = bribe.bribeTokenAmount * sub(sharesAllocatedByUser, _deltaShares)
                    / (sub(totalAllocatedShares, _deltaShares));
                if (bribeTokenAmount != 0) {
                    bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
                }
            }
        }
    }

    /// @inheritdoc IBaseInitiative
    function claimBribes(address _user) external returns (uint256, uint256) {
        return _claimBribes(_user, allocatedAtEpoch[_user], governance.epoch(), 0);
    }

    /// @inheritdoc IInitiative
    function onRegisterInitiative() external virtual override {}

    /// @inheritdoc IInitiative
    function onUnregisterInitiative() external virtual override {}

    /// @inheritdoc IInitiative
    function onAfterAllocateShares(address _user, int256 _deltaShares, int256) external virtual {
        require(msg.sender == address(governance), "BaseInitiative: invalid-sender");

        uint16 currentEpoch = governance.epoch();

        // claim accrued bribes from previous epochs
        _claimBribes(_user, allocatedAtEpoch[_user], currentEpoch, _deltaShares);

        allocatedAtEpoch[_user] = currentEpoch;
    }

    /// @inheritdoc IInitiative
    function onClaimForInitiative(uint256) external virtual override {}
}
