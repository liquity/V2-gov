// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {DoubleLinkedList} from "../src/utils/DoubleLinkedList.sol";

contract DoubleLinkedListWrapper {
    using DoubleLinkedList for DoubleLinkedList.List;

    DoubleLinkedList.List list;

    function getHead() public view returns (uint16) {
        return list.getHead();
    }

    function getTail() public view returns (uint16) {
        return list.getTail();
    }

    function getNext(uint16 id) public view returns (uint16) {
        return list.getNext(id);
    }

    function getPrev(uint16 id) public view returns (uint16) {
        return list.getPrev(id);
    }

    function insert(uint16 id, uint16 next) public {
        list.insert(id, 1, next);
    }

    function remove(uint16 id) public {
        list.remove(id);
    }
}

contract DoubleLinkedListTest is Test {
    DoubleLinkedListWrapper internal wrapper;

    function setUp() public {
        wrapper = new DoubleLinkedListWrapper();
    }

    // next != head: insert before next
    // prev = list.items[next].prev:  prevItem
    // list.items[next].prev = id:    next's prev pointer set from prevItem -> new item
    // list.items[prev].next = id:    prev's next pointer set from next -> new item
    // list.items[id].prev = prev:    new item's prev pointer set to prevItem
    // list.items[id].next = next:    new item's next pointer set to next
    function test_insert_random() public {
        vm.expectRevert(DoubleLinkedList.IdIsZero.selector);
        wrapper.insert(0, 0);

        wrapper.insert(1, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, 1);
        assertEq(wrapper.getHead(), 2);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(3, 2);
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(4, 2);
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 1);

        vm.expectRevert(DoubleLinkedList.ItemInList.selector);
        wrapper.insert(4, 2);

        vm.expectRevert(DoubleLinkedList.ItemNotInList.selector);
        wrapper.insert(5, 10);

        vm.expectRevert(DoubleLinkedList.IdIsZero.selector);
        wrapper.remove(0);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 1);
        assertEq(wrapper.getNext(3), 4);
        assertEq(wrapper.getNext(4), 2);
        assertEq(wrapper.getPrev(1), 2);
        assertEq(wrapper.getPrev(2), 4);
        assertEq(wrapper.getPrev(4), 3);
        assertEq(wrapper.getPrev(3), 0);

        wrapper.remove(1); // remove tail
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 2);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 4);
        assertEq(wrapper.getNext(4), 2);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 4);
        assertEq(wrapper.getPrev(4), 3);
        assertEq(wrapper.getPrev(3), 0);

        vm.expectRevert(DoubleLinkedList.ItemNotInList.selector);
        wrapper.remove(1);

        wrapper.remove(3); // remove head
        assertEq(wrapper.getHead(), 4);
        assertEq(wrapper.getTail(), 2);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 0);
        assertEq(wrapper.getNext(4), 2);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 4);
        assertEq(wrapper.getPrev(4), 0);
        assertEq(wrapper.getPrev(3), 0);

        wrapper.insert(3, 4);
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 2);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 4);
        assertEq(wrapper.getNext(4), 2);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 4);
        assertEq(wrapper.getPrev(4), 3);
        assertEq(wrapper.getPrev(3), 0);

        wrapper.remove(4); // remove center
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 2);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 2);
        assertEq(wrapper.getNext(4), 0);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 3);
        assertEq(wrapper.getPrev(4), 0);
        assertEq(wrapper.getPrev(3), 0);

        wrapper.remove(3); // remove second to last
        assertEq(wrapper.getHead(), 2);
        assertEq(wrapper.getTail(), 2);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 0);
        assertEq(wrapper.getNext(4), 0);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 0);
        assertEq(wrapper.getPrev(4), 0);
        assertEq(wrapper.getPrev(3), 0);

        wrapper.remove(2); // remove last
        assertEq(wrapper.getHead(), 0);
        assertEq(wrapper.getTail(), 0);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 0);
        assertEq(wrapper.getNext(3), 0);
        assertEq(wrapper.getNext(4), 0);
        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 0);
        assertEq(wrapper.getPrev(4), 0);
        assertEq(wrapper.getPrev(3), 0);
    }

    // next == head: insert as new head
    // prev = list.items[next].prev:  nullItem
    // list.items[next].prev = id:    head's prev pointer set from nullItem -> new head
    // list.items[prev].next = id:    nullItem's next pointer set from old head -> new head
    // list.items[id].prev = prev:    new head's prev pointer set to nullItem
    // list.items[id].next = next:    new head's next pointer set to old head
    function test_insert_atHead() public {
        wrapper.insert(1, wrapper.getHead());
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, wrapper.getHead());
        assertEq(wrapper.getHead(), 2);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(3, wrapper.getHead());
        assertEq(wrapper.getHead(), 3);
        assertEq(wrapper.getTail(), 1);

        assertEq(wrapper.getNext(1), 0);
        assertEq(wrapper.getNext(2), 1);
        assertEq(wrapper.getNext(3), 2);

        assertEq(wrapper.getPrev(1), 2);
        assertEq(wrapper.getPrev(2), 3);
        assertEq(wrapper.getPrev(3), 0);
    }

    // next == 0: insert as new tail
    // prev = list.items[next].prev:  old tail
    // list.items[next].prev = id:    nullItem's tail pointer set from old tail -> new tail
    // if list.items[next].next == 0: nullItem's head pointer set to new head / tail
    // list.items[prev].next = id:    old tail's next pointer set from nullItem -> new tail
    // list.items[id].prev = prev:    new tail's prev pointer set to old tail
    // list.items[id].next = next:    new tail's next pointer set to nullItem
    function test_insert_atTail() public {
        wrapper.insert(1, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 1);

        wrapper.insert(2, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 2);

        wrapper.insert(3, 0);
        assertEq(wrapper.getHead(), 1);
        assertEq(wrapper.getTail(), 3);

        assertEq(wrapper.getNext(0), 1);
        assertEq(wrapper.getNext(1), 2);
        assertEq(wrapper.getNext(2), 3);
        assertEq(wrapper.getNext(3), 0);

        assertEq(wrapper.getPrev(1), 0);
        assertEq(wrapper.getPrev(2), 1);
        assertEq(wrapper.getPrev(3), 2);
        assertEq(wrapper.getPrev(0), 3);
    }
}
