// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./contracts-upgradeable/proxy/utils/Initializable.sol";
import "./contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./contracts-upgradeable/utils/StringsUpgradeable.sol";
import "./contracts-upgradeable/utils/ArraysUpgradeable.sol";
import "./contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "./contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/**
 * @title Book
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Book is Initializable, ReentrancyGuardUpgradeable, EIP712Upgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMathUpgradeable for uint256;

    // Structs -----------------------------------------
    struct Copy {
        address owner;
        address lockedWith;
        bool onSale;
        uint256 sellingPrice;
    }

    struct BookVoucher {
        uint256 bookID;
        address receiver;
        uint256 price;
        bytes signature;
    }

    struct Contributor {
        address contributorAddress;
        uint96 share;
    }

    // Storage Variables -----------------------------------------
    CountersUpgradeable.Counter private _pricedBookUid;
    CountersUpgradeable.Counter private _freeBookUid;
    uint256 private _bookId;
    bytes32 private _uri;
    bytes32 private _coverPageUri;
    uint256 private _price;
    uint256 public _royalty;
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
    mapping(address => int96) private flowBalances;

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
        uint256 totalRevenue,
        uint256 withdrawableRevenue,
        uint256 pricedBookSupplyLimit,
        bool supplyLimited,
        Contributor[] calldata contributors
    ) public initializer {
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);
        __ReentrancyGuard_init();

        _bookId = bookId;
        _uri = bookUri;
        _coverPageUri = coverPageUri;
        _price = price;
        _royalty = royalty;
        _totalRevenue = totalRevenue;
        _withdrawableRevenue = withdrawableRevenue;
        _pricedBookSupplyLimit = pricedBookSupplyLimit;
        _supplyLimited = supplyLimited;
        _publisher = msg.sender;

        // Counters incremented to 1
        _pricedBookUid.increment();
        _freeBookUid.increment();

        // Minting FreeBooks to all Contributors
        for (uint256 i = 0; i < contributors.length; i++) {
            _contributors.push(contributors[i]);
            _distributionRecord[_freeBookUid.current()] = contributors[i]
                .contributorAddress;
            _freeBookUid.increment();
        }
        // TODO: emit event
    }

    // Private Functions ---------------------------------
    function _onlyPublusher(address msgSender) private view {
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

    //  verify(BookVoucher)
    function _verify(BookVoucher calldata voucher)
        private
        view
        returns (address)
    {
        bytes32 digest = hash(voucher);
        return ECDSAUpgradeable.recover(digest, voucher.signature);
    }

    function _addRevenue(uint256 incrementBy) private {
        _totalRevenue = _totalRevenue.add(incrementBy);
        _withdrawableRevenue = _withdrawableRevenue.add(incrementBy);
        // TODO: emit event
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
        Copy memory newCopy = Copy(msg.sender, address(0), false, _price);
        _pricedCopiesRecord[_pricedBookUid.current()] = newCopy;
        _pricedBookUid.increment();
        _addRevenue(_price);
        payable(msg.sender).transfer(msg.value.sub(_price));
        // TODO: emit event
    }

    //  buyFromPeer
    function buyFromPeer(uint256 copyUid) external payable nonReentrant {
        require(copyUid < _pricedBookUid.current(), "Invalid CopyUID");
        require(
            msg.value >= _pricedCopiesRecord[copyUid].sellingPrice,
            "Insufficient Funds"
        );
        require(
            _pricedCopiesRecord[copyUid].lockedWith == address(0),
            "Book Locked"
        );
        address previousOwner = _pricedCopiesRecord[copyUid].owner;
        _pricedCopiesRecord[copyUid].owner = msg.sender;
        _pricedCopiesRecord[copyUid].onSale = false;
        _addRevenue(_royalty);
        payable(previousOwner).transfer(
            _pricedCopiesRecord[copyUid].sellingPrice.sub(_royalty)
        );
        payable(msg.sender).transfer(
            msg.value.sub(_pricedCopiesRecord[copyUid].sellingPrice)
        );
        // TODO: emit event
    }

    function transfer(address to, uint256 copyUid)
        external
        payable
        nonReentrant
    {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        require(msg.value >= _royalty, "Insufficient Funds");
        _pricedCopiesRecord[copyUid].owner = to;
        _pricedCopiesRecord[copyUid].onSale = false;
        _addRevenue(_royalty);
        payable(msg.sender).transfer(msg.value.sub(_royalty));
        // TODO: emit event
    }

    // function updatePrice(uint256 newPrice, bytes32 metadataUri)
    function updatePrice(uint256 newPrice) external nonReentrant {
        _onlyPublusher(msg.sender);
        _price = newPrice;
        // TODO: emit event
    }

    function updateSellingPrice(uint256 copyUid, uint256 newSellingPrice)
        external
        nonReentrant
    {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        require(newSellingPrice >= _royalty, "Selling Price Less Than Royalty");
        _pricedCopiesRecord[copyUid].sellingPrice = newSellingPrice;
        // TODO: emit event
    }

    function putOnSale(uint256 copyUid) external nonReentrant {
        _onlyOwner(msg.sender, copyUid);
        _bookUnlocked(copyUid);
        if (!_pricedCopiesRecord[copyUid].onSale)
            _pricedCopiesRecord[copyUid].onSale = true;
    }

    function removeFromSale(uint256 copyUid) external nonReentrant {
        _onlyOwner(msg.sender, copyUid);
        if (_pricedCopiesRecord[copyUid].onSale)
            _pricedCopiesRecord[copyUid].onSale = false;
        // TODO: emit event
    }

    //  increaseMarketSupply - onlyPublisher
    //                     - (unLimit, limit, increaseMarketSupply)
    function increaseMarketSupply(uint256 incrementSupplyBy)
        external
        nonReentrant
    {
        _onlyPublusher(msg.sender);
        require(_supplyLimited, "Supply Not Limited");
        _pricedBookSupplyLimit += incrementSupplyBy;
        // TODO: emit event
    }

    function unlimitSupply() external nonReentrant {
        require(_supplyLimited, "Supply Already Unlimited");
        _supplyLimited = false;
        // TODO: emit event
    }

    function limitSupply() external nonReentrant {
        require(!_supplyLimited, "Supply Already Limited");
        _supplyLimited = true;
        _pricedBookSupplyLimit = _pricedBookUid.current() - 1;
        // TODO: emit event
    }

    //  updateRoyalty - onlyPushlisher
    // function updateRoyalty(uint8 newRoyalty, bytes32 metadataUri)
    function updateRoyalty(uint8 newRoyalty) external nonReentrant {
        _onlyPublusher(msg.sender);
        _royalty = newRoyalty;
        // TODO: emit event
    }

    //  updateCoverPageUri - onlyPushlisher
    // function updateCoverPageUri(bytes32 newCoverPageUri, bytes32 metadataUri)
    function updateCoverPageUri(bytes32 newCoverPageUri) external nonReentrant {
        _onlyPublusher(msg.sender);
        _coverPageUri = newCoverPageUri;
        // TODO: emit event
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
        _onlyPublusher(msg.sender);
        return _withdrawableRevenue;
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
        _distributionRecord[_freeBookUid.current()] = voucher.receiver;
        _freeBookUid.increment();
        _addRevenue(voucher.price);
        payable(msg.sender).transfer(msg.value.sub(voucher.price));
        //TODO: emit event
    }

    function getChainID() external view returns (uint256 id) {
        id = block.chainid;
    }

    //  addContributor - onlyPushlisher
    function addConributor(Contributor calldata newContributor)
        external
        nonReentrant
    {
        _onlyPublusher(msg.sender);
        _contributors.push(newContributor);
        // TODO: emit event
    }

    //  removeContributor - onlyPushlisher
    function removeConributor(address contributor) external nonReentrant {
        _onlyPublusher(msg.sender);
        for (uint256 i = 0; i < _contributors.length; i++) {
            if (_contributors[i].contributorAddress == contributor) {
                _contributors[i] = _contributors[_contributors.length - 1];
                delete _contributors[_contributors.length - 1];
                break;
            }
        }
        // TODO: emit event
    }

    //  updateShares - onlyPushlisher
    function updateContributorShares(address contributor, uint8 share)
        external
        nonReentrant
    {
        _onlyPublusher(msg.sender);
        for (uint256 i = 0; i < _contributors.length; i++) {
            if (_contributors[i].contributorAddress == contributor) {
                _contributors[i].share = share;
                break;
            }
        }
        // TODO: emit event
    }

    function withdrawRevenue() external payable nonReentrant {
        _onlyPublusher(msg.sender);
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
        // TODO: emit event
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
        // TODO: emit event
    }

    function unlock(uint256 copyUid) external nonReentrant {
        require(
            _pricedCopiesRecord[copyUid].lockedWith == msg.sender,
            "Un-authorized Request"
        );
        _pricedCopiesRecord[copyUid].lockedWith = address(0);
        // TODO: emit event
    }

    function verifyLockedWith(address to, uint256 copyUid)
        external
        nonReentrant
        returns (bool)
    {
        return _pricedCopiesRecord[copyUid].lockedWith == to;
    }

    // The Graph -----------------------------------------
    // - Book
    //      - publishedOn
    //      - metadatUri
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
