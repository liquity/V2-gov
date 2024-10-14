// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DoubleLinkedList
/// @notice Implements a double linked list where the head is defined as the null item's prev pointer
/// and the tail is defined as the null item's next pointer ([tail][prev][item][next][head])
library DoubleLinkedList {
    struct Item {
        uint224 value;
        uint16 prev;
        uint16 next;
    }

    struct List {
        mapping(uint16 => Item) items;
    }

    error IdIsZero();
    error ItemNotInList();
    error ItemInList();

    /// @notice Returns the head item id of the list
    /// @param list Linked list which contains the item
    /// @return _ Id of the head item
    function getHead(List storage list) internal view returns (uint16) {
        return list.items[0].prev;
    }

    /// @notice Returns the tail item id of the list
    /// @param list Linked list which contains the item
    /// @return _ Id of the tail item
    function getTail(List storage list) internal view returns (uint16) {
        return list.items[0].next;
    }

    /// @notice Returns the item id which follows item `id`. Returns the head item id of the list if the `id` is 0.
    /// @param list Linked list which contains the items
    /// @param id Id of the current item
    /// @return _ Id of the current item's next item
    function getNext(List storage list, uint16 id) internal view returns (uint16) {
        return list.items[id].next;
    }

    /// @notice Returns the item id which precedes item `id`. Returns the tail item id of the list if the `id` is 0.
    /// @param list Linked list which contains the items
    /// @param id Id of the current item
    /// @return _ Id of the current item's previous item
    function getPrev(List storage list, uint16 id) internal view returns (uint16) {
        return list.items[id].prev;
    }

    /// @notice Returns the value of item `id`
    /// @param list Linked list which contains the item
    /// @param id Id of the item
    /// @return _ Value of the item
    function getValue(List storage list, uint16 id) internal view returns (uint224) {
        return list.items[id].value;
    }

    /// @notice Returns the item `id`
    /// @param list Linked list which contains the item
    /// @param id Id of the item
    /// @return _ Item
    function getItem(List storage list, uint16 id) internal view returns (Item memory) {
        return list.items[id];
    }

    /// @notice Returns whether the list contains item `id`
    /// @param list Linked list which should contain the item
    /// @param id Id of the item to check
    /// @return _ True if the list contains the item, false otherwise
    function contains(List storage list, uint16 id) internal view returns (bool) {
        if (id == 0) revert IdIsZero();
        return (list.items[id].prev != 0 || list.items[id].next != 0 || list.items[0].next == id);
    }

    /// @notice Inserts an item with `id` in the list before item `next`
    /// - if `next` is 0, the item is inserted at the start (head) of the list
    /// @dev This function should not be called with an `id` that is already in the list.
    /// @param list Linked list which contains the next item and into which the new item will be inserted
    /// @param id Id of the item to insert
    /// @param value Value of the item to insert
    /// @param next Id of the item which should follow item `id`
    function insert(List storage list, uint16 id, uint224 value, uint16 next) internal {
        if (contains(list, id)) revert ItemInList();
        if (next != 0 && !contains(list, next)) revert ItemNotInList();
        uint16 prev = list.items[next].prev;
        list.items[prev].next = id;
        list.items[next].prev = id;
        list.items[id].prev = prev;
        list.items[id].next = next;
        list.items[id].value = value;
    }
}
