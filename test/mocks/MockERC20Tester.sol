// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract MockERC20Tester is MockERC20 {
    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(address recipient, uint256 mintAmount, string memory name, string memory symbol, uint8 decimals) {
        super.initialize(name, symbol, decimals);
        _mint(recipient, mintAmount);

        owner = msg.sender;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
