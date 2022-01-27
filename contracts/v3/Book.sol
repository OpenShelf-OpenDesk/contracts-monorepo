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
import "./contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

/**
 * @title Book
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Book is ReentrancyGuardUpgradeable, EIP712Upgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMathUpgradeable for uint256;

    // Structs -----------------------------------------
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
    mapping(uint256 => address) private _pricedCopiesRecord; // copyUID --> previousOwner address
    mapping(address => uint256[]) private _claimedOwnershipRecord; // address --> priced claimedCopyUIDs
    mapping(address => uint256[]) private _unclaimedOwnershipRecord; // address --> priced unclaimedCopyUIDs
    mapping(address => uint256) private _distributionRecord; // address --> free copyUIDs

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
            _distributionRecord[
                contributors[i].contributorAddress
            ] = _freeBookUid.current();
            _freeBookUid.increment();
        }
        // TODO: emit event
    }

    // Private Functions ---------------------------------
    function _onlyPublusher(address msgSender) private view {
        require(msgSender == _publisher, "Un-authorized Request");
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

    function _internalTransfer(
        uint256 copyUid,
        uint256[] storage fromArray,
        uint256[] storage toArray
    ) private {
        uint256 index;
        // getting index of copyUid in msg.sender ownership record
        index = ArraysUpgradeable.findUpperBound(fromArray, copyUid);
        // reverting if copyUid not found
        require(
            index != 0 || index != fromArray.length,
            "Invalid Transfer Request"
        );
        // removing copyUid from msg.sender ownership record
        for (uint256 i = index; i < fromArray.length - 1; i++) {
            fromArray[i] = _claimedOwnershipRecord[msg.sender][i + 1];
        }
        delete fromArray[fromArray.length - 1];
        // adding copyUid in to's ownership record in assending order
        index = ArraysUpgradeable.findUpperBound(toArray, copyUid);
        toArray.push(copyUid);
        for (uint256 j = index; j < toArray.length; j++) {
            uint256 temp = toArray[j];
            toArray[j] = copyUid;
            copyUid = temp;
        }
        // TODO: emit event
    }

    function _addRevenue(uint256 incrementBy) private {
        _totalRevenue = _totalRevenue.add(incrementBy);
        _withdrawableRevenue = _withdrawableRevenue.add(incrementBy);
    }

    // External Functions --------------------------------
    //  buy
    function buy(uint256 copies) external payable nonReentrant {
        require(msg.value >= _price.mul(copies), "Insufficient Funds");
        if (_supplyLimited) {
            require(
                _pricedBookSupplyLimit >
                    _pricedBookUid.current().sub(1).add(copies),
                "Supply Limit Reached"
            );
        }
        for (uint256 i = 0; i < copies; i++) {
            _pricedCopiesRecord[_pricedBookUid.current()] = _publisher;
            _claimedOwnershipRecord[msg.sender].push(_pricedBookUid.current());
            _pricedBookUid.increment();
        }
        _addRevenue(_price.mul(copies));
        payable(msg.sender).transfer(msg.value.sub(_price.mul(copies)));
        // TODO: emit event
    }

    //  transfer
    function transferClaimedAsClaimed(uint256 copyUid, address to)
        external
        payable
        nonReentrant
    {
        require(msg.value >= _royalty, "Insufficient Funds");
        _internalTransfer(
            copyUid,
            _claimedOwnershipRecord[msg.sender],
            _claimedOwnershipRecord[to]
        );
        _addRevenue(_royalty);
        payable(msg.sender).transfer(msg.value.sub(_royalty));
    }

    function transferUnclaimedAsClaimed(uint256 copyUid, address to)
        external
        payable
        nonReentrant
    {
        require(msg.value >= _royalty, "Insufficient Funds");
        _internalTransfer(
            copyUid,
            _unclaimedOwnershipRecord[msg.sender],
            _claimedOwnershipRecord[to]
        );
        _addRevenue(_royalty);
        payable(msg.sender).transfer(msg.value.sub(_royalty));
    }

    function transferClaimedAsUnclaimed(uint256 copyUid, address to)
        external
        nonReentrant
    {
        _internalTransfer(
            copyUid,
            _claimedOwnershipRecord[msg.sender],
            _unclaimedOwnershipRecord[to]
        );
    }

    function transferUnclaimedAsUnclaimed(uint256 copyUid, address to)
        external
        nonReentrant
    {
        _internalTransfer(
            copyUid,
            _unclaimedOwnershipRecord[msg.sender],
            _unclaimedOwnershipRecord[to]
        );
    }

    // Seller > Exchange (transferUnclaimed)
    // Exchange > Buyer (transferUnclaimed)
    // Buyer > Book (claimOwnership) - cutRoyalty
    // transfer - cutRoyalty

    //  updatePrice - onlyPushlisher
    // function updatePrice(uint256 newPrice, bytes32 metadataUri)
    function updatePrice(uint256 newPrice) external nonReentrant {
        _onlyPublusher(msg.sender);
        _price = newPrice;
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
        // getting index of copyUid in msg.sender ownership record
        (bool verified, ) = this.verifyOwnership(msg.sender, copyUid, true);
        require(verified, "Permission Denied");
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
        _distributionRecord[voucher.receiver] = _freeBookUid.current();
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

    function getPreviousOwner(uint256 copyUid) external view returns (address) {
        return _pricedCopiesRecord[copyUid];
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
    }

    function verifyOwnership(
        address owner,
        uint256 copyUid,
        bool claimed
    ) external view returns (bool, uint256) {
        uint256[] storage ownershipRecord;
        if (claimed) {
            ownershipRecord = _claimedOwnershipRecord[owner];
        } else {
            ownershipRecord = _unclaimedOwnershipRecord[owner];
        }
        uint256 index;
        // getting index of copyUid in msg.sender ownership record
        index = ArraysUpgradeable.findUpperBound(ownershipRecord, copyUid);
        // reverting if copyUid not found
        if (index != 0 || index != ownershipRecord.length) {
            return (true, index);
        } else {
            return (false, index);
        }
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
