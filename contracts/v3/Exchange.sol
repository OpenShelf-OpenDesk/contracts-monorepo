// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./contracts-upgradeable/proxy/utils/Initializable.sol";
import "./contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./Book.sol";

/**
 * @title Exchange
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Exchange is
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    // Mappings --------------------------------------------
    // - offers - {bookAddress --> {copyUid --> {buyerAddress --> OfferPrice}}}
    mapping(address => mapping(uint256 => mapping(address => uint256))) _offers;

    // Events -----------------------------------------
    event OfferMade();
    event OfferCancelled();
    event OfferAccepted();

    // Initializer -----------------------------------------
    function initialize() public initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Ownable_init();
    }

    // External Function -----------------------------------
    // makeOffer
    function makeOffer(
        address bookAddress,
        uint256 copyUid,
        uint256 offerPrice
    ) external payable nonReentrant {
        require(msg.value >= offerPrice, "Insufficient Funds");
        require(
            !Book(bookAddress).verifyOwnership(msg.sender, copyUid, false),
            "Invalid Request"
        );
        require(
            offerPrice > _offers[bookAddress][copyUid][msg.sender],
            "Invalid Offer"
        );
        _offers[bookAddress][copyUid][msg.sender] = offerPrice;
        payable(msg.sender).transfer(msg.value.sub(offerPrice));
        // TODO: emit event
        emit OfferMade();
    }

    // cancelOffer
    function cancelOffer(address bookAddress, uint256 copyUid)
        external
        payable
        nonReentrant
    {
        require(
            !Book(bookAddress).verifyOwnership(msg.sender, copyUid, false),
            "Invalid Request"
        );
        uint256 offeredPrice = _offers[bookAddress][copyUid][msg.sender];
        if (offeredPrice > 0) {
            delete _offers[bookAddress][copyUid][msg.sender];
            payable(msg.sender).transfer(offeredPrice);
        }
        // TODO: emit event
        emit OfferCancelled();
    }

    // offerAccepted
    function offerAccepted(
        address bookAddress,
        uint256 copyUid,
        address buyer
    ) external payable nonReentrant {
        Book book = Book(bookAddress);
        require(
            book.getPreviousOwner(copyUid) == msg.sender,
            "Un-authorized Request"
        );
        require(book.verifyOwnership(buyer, copyUid, false), "Invalid Request");
        uint256 offeredPrice = _offers[bookAddress][copyUid][buyer];
        if (offeredPrice > 0) {
            delete _offers[bookAddress][copyUid][buyer];
            payable(msg.sender).transfer(offeredPrice);
        }
        // TODO: emit event
        emit OfferAccepted();
    }

    function _authorizeUpgrade(
        address /*newImplementation*/
    ) internal view override onlyOwner {}
}
