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
        string metadataUri,
        string coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 edition,
        uint256 prequel,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit,
        address indexed bookAddress
    );

    constructor() {
        _bookId.increment();
    }

    // Public Functions -----------------------------------------
    function publish(
        string memory uri,
        string memory metadataUri,
        string memory coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 edition,
        uint256 prequel,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit
    ) external {
        Book newBook = new Book();
        uint256 bookId = _bookId.current();
        newBook.initialize(
            bookId,
            uri,
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
