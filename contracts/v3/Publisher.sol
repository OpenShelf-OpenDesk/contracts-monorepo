// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts-upgradeable/utils/CountersUpgradeable.sol";

import "./Book.sol";

contract Publisher {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    // Storage Variables -----------------------------------------
    CountersUpgradeable.Counter private _bookID;
    mapping(uint256 => address) private publishedBooks;

    event BookPublished(
        uint256 bookId,
        bytes32 metadataUri,
        bytes32 coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 edition,
        address indexed prequel,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit
    );

    constructor() {
        _bookID.increment();
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
        uint256 bookId = _bookID.current();
        newBook.initialize(
            bookId,
            uri,
            coverPageUri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited
        );
        publishedBooks[_bookID.current()] = address(newBook);
        emit BookPublished(
            bookId,
            metadataUri,
            coverPageUri,
            price,
            royalty,
            edition,
            prequel,
            supplyLimited,
            pricedBookSupplyLimit
        );
        _bookID.increment();
    }

    function getBookAddress(uint256 bookId) external view returns (address) {
        return publishedBooks[bookId];
    }
}
