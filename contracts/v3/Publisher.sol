// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts/Counters.sol";
import "./Book.sol";

contract Publisher {
    using Counters for Counters.Counter;

    // Storage Variables -----------------------------------------
    Counters.Counter private _bookId;
    mapping(uint256 => address) private publishedBooks;

    event BookPublished(
        uint256 bookId,
        address indexed publisher,
        bytes32 metadataUri,
        bytes32 coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 edition,
        address indexed prequel,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit,
        address indexed bookAddress
    );

    constructor() {
        _bookId.increment();
    }

    // Public Functions -----------------------------------------
    function publish(
        bytes32 uri,
        bytes32 metadataUri,
        bytes32 coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 edition,
        address prequel,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit
    ) external {
        Book newBook = new Book();
        uint256 bookId = _bookId.current();
        newBook.initialize(
            bookId,
            uri,
            coverPageUri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            msg.sender
        );
        publishedBooks[_bookId.current()] = address(newBook);
        emit BookPublished(
            bookId,
            msg.sender,
            metadataUri,
            coverPageUri,
            price,
            royalty,
            edition,
            prequel,
            supplyLimited,
            pricedBookSupplyLimit,
            address(newBook)
        );
        _bookId.increment();
    }

    function getBookAddress(uint256 bookId) external view returns (address) {
        return publishedBooks[bookId];
    }
}
