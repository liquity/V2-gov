// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {DoubleLinkedList} from "../src/utils/DoubleLinkedList.sol";

contract DoubleLinkedListWrapper {
    using DoubleLinkedList for DoubleLinkedList.List;

    DoubleLinkedList.List list;

    function getHead() public view returns (uint256) {
        return list.getHead();
    }

    function getTail() public view returns (uint256) {
        return list.getTail();
    }

    function getNext(uint256 id) public view returns (uint256) {
        return list.getNext(id);
    }

    function getPrev(uint256 id) public view returns (uint256) {
        return list.getPrev(id);
    }

    function insert(uint256 id, uint256 next) public {
        list.insert(id, 1, 1, next);
    }
}

contract DoubleLinkedListTest is Test {
    DoubleLinkedListWrapper internal wrapper;

    function setUp() public {
        wrapper = new DoubleLinkedListWrapper();
    }

    // next != head: insert before next
    function test_insert_random() public {
        vm.expectRevert(DoubleLinkedList.IdIsZero.selector);
        wrapper.insert(0, 0);

        wrapper.insert(1, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, 1);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 2);

        wrapper.insert(3, 2);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 3);

        wrapper.insert(4, 2);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 3);

        vm.expectRevert(DoubleLinkedList.ItemInList.selector);
        wrapper.insert(4, 2);

        vm.expectRevert(DoubleLinkedList.ItemNotInList.selector);
        wrapper.insert(5, 10);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 1);
        assertEq(wrapper.getNext(3), 4);
        assertEq(wrapper.getNext(4), 2);
        assertEq(wrapper.getPrev(1), 2);
        assertEq(wrapper.getPrev(2), 4);
        assertEq(wrapper.getPrev(4), 3);
        assertEq(wrapper.getPrev(3), 0);
    }

    // next == 0: insert as new head
    function test_insert_atHead() public {
        wrapper.insert(1, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, 0);
        assertEq(wrapper.getHead(), 2);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(3, 0);
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 1);

        assertEq(wrapper.getNext(1), 2);
        assertEq(wrapper.getNext(2), 3);
        assertEq(wrapper.getNext(3), 0);

        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 1);
        assertEq(wrapper.getPrev(3), 2);
    }

    // next == tail: insert as new tail
    function test_insert_atTail() public {
        wrapper.insert(1, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, wrapper.getTail());
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 2);

        wrapper.insert(3, wrapper.getTail());
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 3);

        assertEq(wrapper.getNext(0), 3);
        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 1);
        assertEq(wrapper.getNext(3), 2);

        assertEq(wrapper.getPrev(1), 2);
        assertEq(wrapper.getPrev(2), 3);
        assertEq(wrapper.getPrev(3), 0);
        assertEq(wrapper.getPrev(0), 1);
    }
}
