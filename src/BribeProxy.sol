// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "./interfaces/IGovernance.sol";

contract BribeProxy {
    IERC20 public immutable lqty;
    IERC20 public immutable lusd;
    IERC20 public immutable bribeToken;

    IGovernance public immutable governance;
    address public immutable initiative;

    uint256 public lastShareBalance;

    struct Delegation {
        uint240 shares;
        uint16 epoch;
    }

    mapping(address => Delegation) public delegatedSharesByUser;
    mapping(uint256 => uint256) public bribeByEpoch;

    constructor(address _governance, address _lqty, address _lusd, address _initiative, address _bribeToken) {
        governance = IGovernance(_governance);
        lqty = IERC20(_lqty);
        lusd = IERC20(_lusd);
        initiative = _initiative;
        bribeToken = IERC20(_bribeToken);
    }

    function depositBribe(uint256 _amount, uint256 _epoch) external {
        bribeToken.transferFrom(msg.sender, address(this), _amount);
        uint16 epoch = governance.epoch();
        require(_epoch >= epoch, "BribeProxy: invalid-epoch");
        bribeByEpoch[_epoch] += _amount;
    }

    function sync() external {
        uint256 shareBalance = governance.sharesByUser(address(this));
        if (shareBalance > lastShareBalance) {
            uint256 shareAmount = shareBalance - lastShareBalance;
            lastShareBalance = shareBalance;

            address[] memory initiatives = new address[](1);
            initiatives[0] = initiative;
            int256[] memory deltaShares = new int256[](1);
            deltaShares[0] = int256(shareAmount);
            int256[] memory deltaVetoShares = new int256[](1);
            deltaVetoShares[0] = int256(0);
            governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

            Delegation memory delegation = delegatedSharesByUser[msg.sender];

            // claim accrued bribes from previous epochs
            if (delegation.epoch < governance.epoch()) {
                (uint256 delegatedShares,) = governance.sharesAllocatedByUser(address(this));
                if (delegatedShares > shareAmount) {
                    bribeToken.transfer(
                        msg.sender,
                        bribeByEpoch[governance.epoch()] * delegation.shares / (delegatedShares - shareAmount)
                    );
                }
            }

            delegation.shares += uint240(shareAmount);
            delegation.epoch = governance.epoch();
            delegatedSharesByUser[msg.sender] = delegation;
        }
    }

    function undelegate(address _to, uint256 _shareAmount) external {
        Delegation memory delegation = delegatedSharesByUser[msg.sender];

        address[] memory initiatives = new address[](1);
        initiatives[0] = initiative;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = -int256(_shareAmount);
        int256[] memory deltaVetoShares = new int256[](1);
        deltaVetoShares[0] = int256(0);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        governance.transferShares(delegation.shares, _to);
    }
}
