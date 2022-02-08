// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts-upgradeable/proxy/utils/Initializable.sol";
import "./contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "./contracts-upgradeable/utils/cryptography/LibSignature.sol";

/**
 * @title Book
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Book is
    Initializable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMathUpgradeable for uint256;
    using LibSignature for bytes32;

    // Structs -----------------------------------------
    struct Copy {
        address owner;
        address previousOwner;
        address lockedWith;
        uint256 sellingPrice;
    }

    struct Contributor {
        address contributorAddress;
        uint96 share;
    }

    struct BookVoucher {
        uint256 bookID;
        address receiver;
        uint256 price;
        bytes signature;
    }

    // Storage Variables -----------------------------------------
    CountersUpgradeable.Counter private _pricedBookUid;
    CountersUpgradeable.Counter private _distributedBookUid;
    uint256 public _bookId;
    bytes32 private _uri;
    bytes32 private _coverPageUri;
    uint256 private _price;
    uint256 private _royalty;
    uint256 private _totalRevenue;
    uint256 private _withdrawableRevenue;
    uint256 private _pricedBookSupplyLimit;
    bool private _supplyLimited;
    address private _publisher;

    // Arrays --------------------------------------------
    Contributor[] private _contributors;

    // Mappings ------------------------------------------
    mapping(uint256 => Copy) private _pricedCopiesRecord; // copyUID --> Copy
    mapping(uint256 => address) private _distributionRecord; // free copyUIDs --> address

    // Events -----------------------------------------
    event BookBought(uint256 copyUid, address indexed buyer, uint256 price);
    event BookTransferred(uint256 copyUid, address indexed to);
    event PriceUpdated(uint256 newPrice);
    event SellingPriceUpdated(uint256 copyUid, uint256 newSellingPrice);
    event MarketSupplyIncreased(uint256 newPricedBookSupplyLimit);
    event SupplyUnlimited();
    event SupplyLimited();
    event RoyaltyUpdated(uint256 newRoyalty);
    event CoverPageUpdated(bytes32 newCoverPageUri);
    event BookRedeemed(
        uint256 distributedCopyUid,
        uint256 price,
        address indexed receiver
    );
    event ContributorAdded(address indexed contributorAddress, uint96 share);
    event ContributorRemoved(address indexed contributorAddress);
    event ContributorUpdated(address indexed contributorAddress, uint96 share);
    event RevenueWithdrawn(uint256 withdrawableRevenue);
    event BookLocked(uint256 copyUid, address indexed to);
    event BookUnlocked(uint256 copyUid);

    // Constants -----------------------------------------
    string private constant SIGNING_DOMAIN = "BOOK-VOUCHER";
    string private constant SIGNATURE_VERSION = "1";

    // Initializer
    function initialize(
        uint256 bookId,
        bytes32 bookUri,
        bytes32 coverPageUri,
        uint256 price,
        uint256 royalty,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited,
        address publisher
    ) public initializer {
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _bookId = bookId;
        _uri = bookUri;
        _coverPageUri = coverPageUri;
        _price = price;
        _royalty = royalty;
        _pricedBookSupplyLimit = pricedBookSupplyLimit;
        _supplyLimited = supplyLimited;
        _publisher = publisher;

        // Counters incremented to 1
        _pricedBookUid.increment();
        _distributedBookUid.increment();
    }

    // Private Functions ---------------------------------
    function _onlyPublisher(address msgSender) private view {
        require(msgSender == _publisher, "Un-authorized Request");
    }

    function _onlyOwner(address msgSender, uint256 copyUid) private view {
        require(
            _pricedCopiesRecord[copyUid].owner == msgSender,
            "Un-authorized Request"
        );
    }

    function _bookUnlocked(uint256 copyUid) private view {
        require(
            _pricedCopiesRecord[copyUid].lockedWith == address(0),
            "Book Locked"
        );
    }

    function _addRevenue(uint256 incrementBy) private {
        _totalRevenue = _totalRevenue.add(incrementBy);
        _withdrawableRevenue = _withdrawableRevenue.add(incrementBy);
    }

    // External Functions --------------------------------
    //  buyFromAuthor
    function buy() external payable nonReentrant {
        require(msg.value >= _price, "Insufficient Funds");
        if (_supplyLimited) {
            require(
                _pricedBookSupplyLimit > _pricedBookUid.current().sub(1),
                "Supply Limit Reached"
            );
        }
        Copy memory newCopy = Copy(msg.sender, _publisher, address(0), _price);
        _pricedCopiesRecord[_pricedBookUid.current()] = newCopy;
        _pricedBookUid.increment();
        _addRevenue(_price);
        payable(msg.sender).transfer(msg.value.sub(_price));
        emit BookBought(_pricedBookUid.current(), msg.sender, _price);
    }

    // buyFromPeer
    // function buyFromPeer(uint256 copyUid) external payable nonReentrant {
    //     require(copyUid < _pricedBookUid.current(), "Invalid CopyUID");
    //     require(
    //         msg.value >= _pricedCopiesRecord[copyUid].sellingPrice,
    //         "Insufficient Funds"
    //     );
    //     require(
    //         _pricedCopiesRecord[copyUid].lockedWith == address(0),
    //         "Book Locked"
    //     );
    //     address previousOwner = _pricedCopiesRecord[copyUid].owner;
    //     _pricedCopiesRecord[copyUid].previousOwner = previousOwner;
    //     _pricedCopiesRecord[copyUid].owner = msg.sender;
    //     _pricedCopiesRecord[copyUid].onSale = false;
    //     _addRevenue(_royalty);
    //     payable(previousOwner).transfer(
    //         _pricedCopiesRecord[copyUid].sellingPrice.sub(_royalty)
    //     );
    //     payable(msg.sender).transfer(
    //         msg.value.sub(_pricedCopiesRecord[copyUid].sellingPrice)
    //     );
    //     // TODO: emit event
    // }

    function transfer(address to, uint256 copyUid)
        external
        payable
        nonReentrant
    {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        require(msg.value >= _royalty, "Insufficient Funds");
        _pricedCopiesRecord[copyUid].previousOwner = msg.sender;
        _pricedCopiesRecord[copyUid].owner = to;
        _addRevenue(_royalty);
        payable(msg.sender).transfer(msg.value.sub(_royalty));
        emit BookTransferred(copyUid, to);
    }

    // function updatePrice(uint256 newPrice, bytes32 metadataUri)
    function updatePrice(uint256 newPrice) external nonReentrant {
        _onlyPublisher(msg.sender);
        _price = newPrice;
        emit PriceUpdated(newPrice);
    }

    function updateSellingPrice(uint256 copyUid, uint256 newSellingPrice)
        external
        nonReentrant
    {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        require(newSellingPrice >= _royalty, "Selling Price Less Than Royalty");
        _pricedCopiesRecord[copyUid].sellingPrice = newSellingPrice;
        emit SellingPriceUpdated(copyUid, newSellingPrice);
    }

    // function putOnSale(uint256 copyUid) external nonReentrant {
    //     _onlyOwner(msg.sender, copyUid);
    //     _bookUnlocked(copyUid);
    //     if (!_pricedCopiesRecord[copyUid].onSale)
    //         _pricedCopiesRecord[copyUid].onSale = true;
    //     // TODO: emit event
    // }

    // function removeFromSale(uint256 copyUid) external nonReentrant {
    //     _onlyOwner(msg.sender, copyUid);
    //     if (_pricedCopiesRecord[copyUid].onSale)
    //         _pricedCopiesRecord[copyUid].onSale = false;
    //     // TODO: emit event
    // }

    //  increaseMarketSupply - onlyPublisher
    //                     - (unLimit, limit, increaseMarketSupply)
    function increaseMarketSupply(uint256 incrementSupplyBy)
        external
        nonReentrant
    {
        _onlyPublisher(msg.sender);
        require(_supplyLimited, "Supply Not Limited");
        _pricedBookSupplyLimit += incrementSupplyBy;
        emit MarketSupplyIncreased(_pricedBookSupplyLimit);
    }

    function unlimitSupply() external nonReentrant {
        require(_supplyLimited, "Supply Already Unlimited");
        _supplyLimited = false;
        emit SupplyUnlimited();
    }

    function limitSupply() external nonReentrant {
        require(!_supplyLimited, "Supply Already Limited");
        _supplyLimited = true;
        _pricedBookSupplyLimit = _pricedBookUid.current() - 1;
        emit SupplyLimited();
    }

    //  updateRoyalty - onlyPushlisher
    // function updateRoyalty(uint8 newRoyalty, bytes32 metadataUri)
    function updateRoyalty(uint256 newRoyalty) external nonReentrant {
        _onlyPublisher(msg.sender);
        _royalty = newRoyalty;
        emit RoyaltyUpdated(newRoyalty);
    }

    //  updateCoverPageUri - onlyPushlisher
    // function updateCoverPageUri(bytes32 newCoverPageUri, bytes32 metadataUri)
    function updateCoverPageUri(bytes32 newCoverPageUri) external nonReentrant {
        _onlyPublisher(msg.sender);
        _coverPageUri = newCoverPageUri;
        emit CoverPageUpdated(newCoverPageUri);
    }

    //  uri - onlyOwner
    function uri(uint256 copyUid) external view returns (bytes32) {
        require(
            (_pricedCopiesRecord[copyUid].lockedWith == address(0) &&
                _pricedCopiesRecord[copyUid].owner == msg.sender) ||
                _pricedCopiesRecord[copyUid].lockedWith == msg.sender ||
                _distributionRecord[copyUid] == msg.sender,
            "Un-authorized Request"
        );
        return _uri;
    }

    //  getWithdrawableRevenue - onlyPushlisher
    function getWithdrawableRevenue() external view returns (uint256) {
        _onlyPublisher(msg.sender);
        return _withdrawableRevenue;
    }

    //  redeem(msg.sender, BookVoucher)
    function redeem(BookVoucher calldata voucher)
        external
        payable
        nonReentrant
    {
        require(msg.value >= voucher.price, "Insufficient Funds");
        address signer = _verify(voucher);
        require(_publisher == signer, "Invalid Signature");
        require(voucher.receiver == msg.sender, "Invalid Request");
        _distributionRecord[_distributedBookUid.current()] = voucher.receiver;
        _distributedBookUid.increment();
        _addRevenue(voucher.price);
        payable(msg.sender).transfer(msg.value.sub(voucher.price));
        //TODO: emit event
        emit BookRedeemed(
            _distributedBookUid.current(),
            voucher.price,
            voucher.receiver
        );
    }

    //  addContributor - onlyPushlisher
    function addConributor(Contributor calldata newContributor)
        external
        nonReentrant
    {
        _onlyPublisher(msg.sender);
        _contributors.push(newContributor);
        _distributionRecord[_distributedBookUid.current()] = newContributor
            .contributorAddress;
        _distributedBookUid.increment();
        emit ContributorAdded(
            newContributor.contributorAddress,
            newContributor.share
        );
    }

    //  removeContributor - onlyPushlisher
    function removeConributor(address contributor) external nonReentrant {
        _onlyPublisher(msg.sender);
        for (uint256 i = 0; i < _contributors.length; i++) {
            if (_contributors[i].contributorAddress == contributor) {
                _contributors[i] = _contributors[_contributors.length - 1];
                delete _contributors[_contributors.length - 1];
                break;
            }
        }
        emit ContributorRemoved(contributor);
    }

    //  updateShares - onlyPushlisher
    function updateContributorShares(address contributor, uint96 share)
        external
        nonReentrant
    {
        _onlyPublisher(msg.sender);
        for (uint256 i = 0; i < _contributors.length; i++) {
            if (_contributors[i].contributorAddress == contributor) {
                _contributors[i].share = share;
                break;
            }
        }
        emit ContributorUpdated(contributor, share);
    }

    function withdrawRevenue() external payable nonReentrant {
        _onlyPublisher(msg.sender);
        uint256 totalShares;
        for (uint256 i = 0; i < _contributors.length; i++) {
            totalShares = totalShares.add(_contributors[i].share);
        }
        uint256 revenuePerUnitShare = _withdrawableRevenue.div(totalShares);
        _withdrawableRevenue = _withdrawableRevenue.mod(totalShares);
        for (uint256 i = 0; i < _contributors.length; i++) {
            payable(_contributors[i].contributorAddress).transfer(
                revenuePerUnitShare.mul(_contributors[i].share)
            );
        }
        emit RevenueWithdrawn(_withdrawableRevenue);
    }

    function verifyOwnership(
        address owner,
        uint256 copyUid,
        bool distributed
    ) external view returns (bool) {
        if (distributed) {
            return _distributionRecord[copyUid] == owner;
        } else {
            return _pricedCopiesRecord[copyUid].owner == owner;
        }
    }

    function lockWith(address to, uint256 copyUid) external nonReentrant {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        _pricedCopiesRecord[copyUid].lockedWith = to;
        emit BookLocked(copyUid, to);
    }

    function unlock(uint256 copyUid) external nonReentrant {
        require(
            _pricedCopiesRecord[copyUid].lockedWith == msg.sender,
            "Un-authorized Request"
        );
        _pricedCopiesRecord[copyUid].lockedWith = address(0);
        emit BookUnlocked(copyUid);
    }

    function verifyLockedWith(address to, uint256 copyUid)
        external
        view
        returns (bool)
    {
        return _pricedCopiesRecord[copyUid].lockedWith == to;
    }

    function getPreviousOwner(uint256 copyUid) external view returns (address) {
        return _pricedCopiesRecord[copyUid].previousOwner;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
    {
        _onlyPublisher(msg.sender);
        require(
            Book(newImplementation)._bookId() == _bookId,
            "Invalid Implementation"
        );
    }

    //  verify(BookVoucher)
    function _verify(BookVoucher calldata voucher)
        private
        view
        returns (address)
    {
        bytes32 digest = hash(voucher);
        return LibSignature.recover(digest, voucher.signature);
    }

    //  hash(BookVoucher)
    function hash(BookVoucher calldata voucher) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "BookVoucher(uint256 bookID,uint256 price,address receiver)"
                        ),
                        voucher.bookID,
                        voucher.price,
                        voucher.receiver
                    )
                )
            );
    }

    function getChainID() external view returns (uint256 id) {
        id = block.chainid;
    }

    // The Graph -----------------------------------------
    // - Book
    //      - publishedOn
    //      - metadataUri
    //      - prequel
    //      - edition
    //      - totalRevenue
    //      - pricedBookPrinter
    //      - freeBookPrinted
    // - Copy
    //      - originalPrice
    //      - purchasedOn
    //      - coverPageURI
    // - DistributedCopy
    //      - originalPrice
    //      - receivedOn
    //      - coverPageURI
}
