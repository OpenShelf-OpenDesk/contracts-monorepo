// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./contracts-upgradeable/proxy/utils/Initializable.sol";
import "./contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./Book.sol";

/**
 * @title Exchange
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Exchange is Initializable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;

    // Mappings --------------------------------------------
    //   - sellerOrders - {bookAddress --> {price --> [Seller(copyUid)]}}
    mapping(address => mapping(uint256 => uint256[])) sellOrders;
    //   - buyerOrders - {bookAddress --> {price --> [Buyer(address)]}}
    mapping(address => mapping(uint256 => address[])) buyOrders;

    // Initializer -----------------------------------------
    function initialize() public initializer {
        __ReentrancyGuard_init();
    }

    // External Function -----------------------------------
    function placeBuyOrder(address bookAddress, uint256 buyPrice)
        external
        payable
        nonReentrant
    {
        Book book = Book(bookAddress);
        uint256 royalty = book._royalty();
        require(msg.value >= buyPrice.add(royalty), "Insufficient Funds");
        if (sellOrders[bookAddress][buyPrice].length > 0) {
            uint256 copyUid = sellOrders[bookAddress][buyPrice][0];
            book.transferUnclaimedAsClaimed{value: royalty}(
                copyUid,
                msg.sender
            );
            address seller = book.getPreviousOwner(copyUid);
            for (
                uint256 i = 0;
                i < sellOrders[bookAddress][buyPrice].length - 1;
                i++
            ) {
                sellOrders[bookAddress][buyPrice][i] = sellOrders[bookAddress][
                    buyPrice
                ][i + 1];
            }
            delete sellOrders[bookAddress][buyPrice][
                sellOrders[bookAddress][buyPrice].length - 1
            ];
            payable(seller).transfer(buyPrice);
        } else {
            buyOrders[bookAddress][buyPrice].push(msg.sender);
        }
        payable(msg.sender).transfer(msg.value.sub(buyPrice.add(royalty)));
    }

    function placeSellOrder(
        address bookAddress,
        uint256 copyUid,
        uint256 sellPrice
    ) external payable nonReentrant {
        Book book = Book(bookAddress);
        uint256 royalty = book._royalty();
        (bool verified, ) = book.verifyOwnership(address(this), copyUid, false);
        require(verified, "Invalid Request");
        if (buyOrders[bookAddress][sellPrice].length > 0) {
            address buyer = buyOrders[bookAddress][sellPrice][0];
            book.transferUnclaimedAsClaimed{value: royalty}(copyUid, buyer);
            for (
                uint256 i = 0;
                i < buyOrders[bookAddress][sellPrice].length - 1;
                i++
            ) {
                buyOrders[bookAddress][sellPrice][i] = buyOrders[bookAddress][
                    sellPrice
                ][i + 1];
            }
            delete buyOrders[bookAddress][sellPrice][
                buyOrders[bookAddress][sellPrice].length - 1
            ];
            payable(msg.sender).transfer(sellPrice);
        } else {
            sellOrders[bookAddress][sellPrice].push(copyUid);
        }
    }
}
