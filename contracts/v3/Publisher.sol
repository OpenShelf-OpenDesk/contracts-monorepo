// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts/Counters.sol";
import "./Edition.sol";

contract Publisher {
    using Counters for Counters.Counter;

    // Storage Variables -----------------------------------------
    Counters.Counter private _bookId;
    Counters.Counter private _seriesId;
    mapping(uint256 => address) private _publishers; // bookId => publisherAddress
    mapping(uint256 => address) private _seriesCreators; // bookId => seriesCreatorAddress

    event NewBookLaunched(
        uint256 bookId,
        address indexed publisher,
        string metadataUri,
        uint256 price,
        uint256 royalty,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited,
        address indexed editionAddress
    );

    event NewEditionLaunched(
        uint256 bookId,
        string metadataUri,
        uint256 price,
        uint256 royalty,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited,
        address indexed editionAddress
    );

    event NewSeriesCreated(
        uint256 seriesId,
        string seriesMetadatUri,
        address indexed publisher
    );

    event AddedBookToSeries(uint256 seriesId, uint256 bookId);

    constructor() {
        _bookId.increment();
        _seriesId.increment();
    }

    function _launchNewEdition(
        uint256 bookId,
        string memory uri,
        uint256 price,
        uint256 royalty,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited,
        address publisher
    ) private returns (address) {
        Edition newBook = new Edition(); // new Edition
        newBook.initialize(
            bookId,
            uri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            publisher
        );
        return address(newBook);
    }

    // Public Functions -----------------------------------------
    function launchNewBook(
        string memory uri,
        string memory metadataUri,
        uint256 price,
        uint256 royalty,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited
    ) external {
        uint256 bookId = _bookId.current();
        _publishers[bookId] = msg.sender;
        address newEditionAddress = _launchNewEdition(
            bookId,
            uri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            msg.sender
        );
        emit NewBookLaunched(
            bookId,
            msg.sender,
            metadataUri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            newEditionAddress
        );
        _bookId.increment();
    }

    // Public Functions -----------------------------------------
    function launchNewEdition(
        uint256 bookId,
        string memory uri,
        string memory metadataUri,
        uint256 price,
        uint256 royalty,
        bool supplyLimited,
        uint256 pricedBookSupplyLimit
    ) external {
        require(_publishers[bookId] == msg.sender, "Un-authorized Request");
        address newEditionAddress = _launchNewEdition(
            bookId,
            uri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            msg.sender
        );
        emit NewEditionLaunched(
            bookId,
            metadataUri,
            price,
            royalty,
            pricedBookSupplyLimit,
            supplyLimited,
            newEditionAddress
        );
    }

    function createSeries(string memory seriesMetadataUri) external {
        uint256 seriesId = _seriesId.current();
        _seriesCreators[seriesId] = msg.sender;
        emit NewSeriesCreated(seriesId, seriesMetadataUri, msg.sender);
        _seriesId.increment();
    }

    function addBookToSeries(uint256 seriesId, uint256 bookId) external {
        require(
            seriesId < _seriesId.current() && bookId < _bookId.current(),
            "Invalid Request"
        );
        require(
            _seriesCreators[seriesId] == msg.sender,
            "Un-authorized Request"
        );
        require(_publishers[bookId] == msg.sender, "Un-authorized Request");
        emit AddedBookToSeries(seriesId, bookId);
    }
}
