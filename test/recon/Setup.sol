
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import {BribeInitiative} from "../../src/BribeInitiative.sol";
import {IBribeInitiative} from "../../src/interfaces/IBribeInitiative.sol";
import {DoubleLinkedList} from "../../src/utils/DoubleLinkedList.sol";
import {MockGovernance} from "../mocks/MockGovernance.sol";
import {MockERC20Tester} from "../mocks/MockERC20Tester.sol";


abstract contract Setup is BaseSetup {
  using DoubleLinkedList for DoubleLinkedList.List;
  
  MockGovernance internal governance;
  MockERC20Tester internal lqty;
  MockERC20Tester internal lusd;
  IBribeInitiative internal initiative;

  address internal user = address(this);
  bool internal claimedTwice;
  mapping(address => DoubleLinkedList.List) internal ghostLqtyAllocationByUserAtEpoch;
  

  function setup() internal virtual override {
      uint256 initialMintAmount = type(uint88).max;
      lqty = new MockERC20Tester(user, initialMintAmount, "Liquity", "LQTY", 18);
      lusd = new MockERC20Tester(user, initialMintAmount, "Liquity USD", "LUSD", 18); // BOLD

      governance = new MockGovernance();
      initiative = IBribeInitiative(address(new BribeInitiative(address(governance), address(lusd), address(lqty))));

      // approve BribeInitiative for user's tokens
      lqty.approve(address(initiative), initialMintAmount);
      lusd.approve(address(initiative), initialMintAmount);
  }
}
