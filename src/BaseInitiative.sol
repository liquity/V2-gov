// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";
import {IInitiative} from "./interfaces/IInitiative.sol";

import {sub} from "./utils/Math.sol";

contract BaseInitiative is IInitiative {
    using SafeERC20 for IERC20;

    IGovernance public immutable governance;
    IERC20 public immutable bold;
    IERC20 public immutable bribeToken;

    mapping(address => uint16) public allocatedSharesByUserAtEpoch;
    mapping(address => uint16) public claimedAtEpoch;
    mapping(uint256 => uint256) public bribeByEpoch;

    constructor(address _governance, address _bold, address _bribeToken) {
        // prohibit the use of BOLD as the bribe token since initiatives are receiving BOLD from Governance
        require(_bold != _bribeToken, "BaseInitiative: invalid-tokens");
        governance = IGovernance(_governance);
        bold = IERC20(_bold);
        bribeToken = IERC20(_bribeToken);
    }

    function depositBribe(uint256 _amount, uint256 _epoch) external {
        bribeToken.transferFrom(msg.sender, address(this), _amount);
        uint16 epoch = governance.epoch();
        require(_epoch >= epoch, "BaseInitiative: invalid-epoch");
        bribeByEpoch[_epoch] += _amount;
    }

    function _claimBribes(address _user, uint16 _lastEpoch, uint16 _currentEpoch, int256 _deltaShares)
        internal
        returns (uint256 amount)
    {
        // claim accrued bribes from previous epochs
        if (_lastEpoch < _currentEpoch) {
            (uint128 totalAllocatedShares,) = governance.sharesAllocatedToInitiative(address(this));
            (uint128 sharesAllocatedByUser, uint128 vetoSharesAllocatedByUser) =
                governance.sharesAllocatedByUserToInitiative(_user, address(this));
            if (int128(totalAllocatedShares) > _deltaShares && vetoSharesAllocatedByUser == 0) {
                uint256 bribe = bribeByEpoch[_currentEpoch];
                amount = bribe * sub(sharesAllocatedByUser, _deltaShares) / (sub(totalAllocatedShares, _deltaShares));
                if (bribe != 0) {
                    bribeToken.transfer(msg.sender, amount);
                }
            }
        }
    }

    function claimBribes(address _user) external returns (uint256) {
        return _claimBribes(_user, allocatedSharesByUserAtEpoch[_user], governance.epoch(), 0);
    }

    function onRegisterInitiative() external virtual override {}

    function onUnregisterInitiative() external virtual override {}

    function onAfterAllocateShares(address _user, int256 _deltaShares, int256) external virtual {
        require(msg.sender == address(governance), "BaseInitiative: invalid-sender");

        uint16 currentEpoch = governance.epoch();

        // claim accrued bribes from previous epochs
        _claimBribes(_user, allocatedSharesByUserAtEpoch[_user], currentEpoch, _deltaShares);

        allocatedSharesByUserAtEpoch[_user] = currentEpoch;
    }

    function onClaimForInitiative(uint256) external virtual override {}
}
