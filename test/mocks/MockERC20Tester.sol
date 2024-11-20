// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20Permit} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ILUSD} from "../../src/interfaces/ILUSD.sol";
import {ILQTY} from "../../src/interfaces/ILQTY.sol";

contract MockERC20Tester is ILUSD, ILQTY, ERC20Permit, Ownable {
    mapping(address spender => bool) public mock_isWildcardSpender;

    constructor(string memory name, string memory symbol) ERC20Permit(name) ERC20(name, symbol) Ownable(msg.sender) {}

    // LUSD & LQTY expose this
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function nonces(address owner) public view virtual override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    function allowance(address owner, address spender) public view virtual override(IERC20, ERC20) returns (uint256) {
        return mock_isWildcardSpender[spender] ? type(uint256).max : super.allowance(owner, spender);
    }

    function mint(address account, uint256 value) external onlyOwner {
        _mint(account, value);
    }

    function mock_setWildcardSpender(address spender, bool allowed) external onlyOwner {
        mock_isWildcardSpender[spender] = allowed;
    }
}
