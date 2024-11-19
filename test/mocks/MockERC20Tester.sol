// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Tester is ERC20, Ownable {
    mapping(address spender => bool) public mock_isWildcardSpender;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return mock_isWildcardSpender[spender] ? type(uint256).max : super.allowance(owner, spender);
    }

    function mock_setWildcardSpender(address spender, bool allowed) external onlyOwner {
        mock_isWildcardSpender[spender] = allowed;
    }

    function mock_mint(address account, uint256 value) external onlyOwner {
        _mint(account, value);
    }
}
