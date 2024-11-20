// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ILQTYStaking} from "../../src/interfaces/ILQTYStaking.sol";

contract MockStakingV1 is ILQTYStaking, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 internal immutable _lqty;
    IERC20 internal immutable _lusd;

    uint256 public totalLQTYStaked;
    EnumerableSet.AddressSet internal _stakers;
    mapping(address staker => uint256) public stakes;
    mapping(address staker => uint256) internal _pendingLUSDGain;
    mapping(address staker => uint256) internal _pendingETHGain;

    constructor(IERC20 lqty, IERC20 lusd) Ownable(msg.sender) {
        _lqty = lqty;
        _lusd = lusd;
    }

    function _resetGains() internal returns (uint256 lusdGain, uint256 ethGain) {
        lusdGain = _pendingLUSDGain[msg.sender];
        ethGain = _pendingETHGain[msg.sender];

        _pendingLUSDGain[msg.sender] = 0;
        _pendingETHGain[msg.sender] = 0;
    }

    function _payoutGains(uint256 lusdGain, uint256 ethGain) internal {
        _lusd.transfer(msg.sender, lusdGain);
        (bool success,) = msg.sender.call{value: ethGain}("");
        require(success, "LQTYStaking: Failed to send accumulated ETHGain");
    }

    function stake(uint256 amount) external override {
        require(amount > 0, "LQTYStaking: Amount must be non-zero");
        uint256 oldStake = stakes[msg.sender];
        (uint256 lusdGain, uint256 ethGain) = oldStake > 0 ? _resetGains() : (0, 0);

        stakes[msg.sender] += amount;
        totalLQTYStaked += amount;
        _stakers.add(msg.sender);

        _lqty.transferFrom(msg.sender, address(this), amount);
        if (oldStake > 0) _payoutGains(lusdGain, ethGain);
    }

    function unstake(uint256 amount) external override {
        require(stakes[msg.sender] > 0, "LQTYStaking: User must have a non-zero stake");
        (uint256 lusdGain, uint256 ethGain) = _resetGains();

        if (amount > 0) {
            uint256 withdrawn = Math.min(amount, stakes[msg.sender]);
            if ((stakes[msg.sender] -= withdrawn) == 0) _stakers.remove(msg.sender);
            totalLQTYStaked -= withdrawn;

            _lqty.transfer(msg.sender, withdrawn);
        }

        _payoutGains(lusdGain, ethGain);
    }

    function getPendingLUSDGain(address user) external view override returns (uint256) {
        return _pendingLUSDGain[user];
    }

    function getPendingETHGain(address user) external view override returns (uint256) {
        return _pendingETHGain[user];
    }

    function setAddresses(address, address, address, address, address) external override {}
    function increaseF_ETH(uint256) external override {}
    function increaseF_LUSD(uint256) external override {}

    function mock_addLUSDGain(uint256 amount) external onlyOwner {
        uint256 numStakers = _stakers.length();
        assert(numStakers == 0 || totalLQTYStaked > 0);

        for (uint256 i = 0; i < numStakers; ++i) {
            address staker = _stakers.at(i);
            assert(stakes[staker] > 0);
            _pendingLUSDGain[staker] += amount * stakes[staker] / totalLQTYStaked;
        }

        _lusd.transferFrom(msg.sender, address(this), amount);
    }

    function mock_addETHGain() external payable onlyOwner {
        uint256 numStakers = _stakers.length();
        assert(numStakers == 0 || totalLQTYStaked > 0);

        for (uint256 i = 0; i < numStakers; ++i) {
            address staker = _stakers.at(i);
            assert(stakes[staker] > 0);
            _pendingETHGain[staker] += msg.value * stakes[staker] / totalLQTYStaked;
        }
    }
}
