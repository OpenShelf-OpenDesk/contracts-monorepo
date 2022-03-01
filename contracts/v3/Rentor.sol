// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
pragma abicoder v2;

import "./contracts/ReentrancyGuard.sol";
import "./contracts/SignedSafeMath.sol";
import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import "./Edition.sol";

/**
 * @title Exchange
 * @author Raghav Goyal, Nonit Mittal
 * @dev
 */
contract Rentor is ReentrancyGuard, SuperAppBase {
    using SignedSafeMath for int96;

    // Structs -----------------------------------------
    struct RentRecord {
        address rentor; // edition owner
        address rentee; // edition rented to
        int96 flowRate;
    }

    struct RenteeRecord {
        address bookAddress;
        uint256 copyUid;
    }

    // Mappings ------------------------------------------
    // - flowBalance {address --> int96 flowRate}
    mapping(address => int96) private _flowBalances;
    // -_rentedBooksRecord {bookAddress --> {copyUid --> Pair{rentee, rentor, flowrate}}}
    mapping(address => mapping(uint256 => RentRecord))
        private _rentedBooksRecord;
    // - {readerAddress --> [Record{bookAddress, copyUid}]}
    mapping(address => RenteeRecord[]) private _renteeRecord;

    // Superfluid -----------------------------------------
    ISuperfluid private _host;
    IConstantFlowAgreementV1 private _cfa;
    ISuperToken private _acceptedToken;

    constructor(
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
    ) {
        require(address(host) != address(0), "Zero Address Not Allowed");
        require(address(cfa) != address(0), "Zero Address Not Allowed");
        require(
            address(acceptedToken) != address(0),
            "Zero Address Not Allowed"
        );
        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    // Events -----------------------------------------
    // event AllBooksReturned();
    event BookPutOnRent(
        address indexed editionAddress,
        uint256 copyUid,
        int96 flowRate
    );
    event BookRemovedFromRent(address indexed editionAddress, uint256 copyUid);
    event BookTakenOnRent(
        address indexed editionAddress,
        uint256 copyUid,
        address indexed rentedTo,
        int96 flowRate
    );

    event BookReturned(address indexed editionAddress, uint256 copyUid);
    // event AddedToWaitingList(address bookAddress, uint256 copyUid);
    // event RemovedFromWaitingList(address bookAddress, uint256 copyUid);

    // Modifiers -----------------------------------------
    modifier onlyHost() {
        require(msg.sender == address(_host), "Support Only One Host");
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "Not Accepted Token");
        require(_isCFAv1(agreementClass), "Only CFAv1 Supported");
        _;
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return
            ISuperAgreement(agreementClass).agreementType() ==
            keccak256(
                "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
            );
    }

    // Private Functions ------------------------------------------------
    function _flowExists(address msgSender) private view {
        require(_flowBalances[msgSender] > 0, "Flow Does Not Exists");
    }

    function _updateFlowFromContractWithCtx(
        address to,
        int96 flowRate,
        bytes memory _ctx
    ) private returns (bytes memory newCtx) {
        int96 existingFlowRate = _getFlowFromContract(to);
        int96 newFlowRate = existingFlowRate.add(flowRate);
        require(newFlowRate >= 0, "Insufficent Flow Balance");
        (newCtx, ) = _host.callAgreementWithContext(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                _acceptedToken,
                to,
                newFlowRate,
                new bytes(0)
            ),
            "0x",
            _ctx
        );
    }

    function _updateFlowFromContract(address to, int96 flowRate) private {
        int96 existingFlowRate = _getFlowFromContract(to);
        int96 newFlowRate = existingFlowRate.add(flowRate);
        require(newFlowRate >= 0, "Insufficent Flow Balance");
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                _acceptedToken,
                to,
                newFlowRate,
                new bytes(0)
            ),
            "0x"
        );
    }

    function _deleteFlowFromContract(address to, bytes memory _ctx)
        private
        returns (bytes memory newCtx)
    {
        (newCtx, ) = _host.callAgreementWithContext(
            _cfa,
            abi.encodeWithSelector(
                _cfa.deleteFlow.selector,
                _acceptedToken,
                address(this),
                to,
                new bytes(0) // placeholder
            ),
            "0x",
            _ctx
        );
    }

    function _createFlowFromAgreement(
        address to,
        int96 flowRate,
        bytes memory _ctx
    ) private returns (bytes memory newCtx) {
        (newCtx, ) = _host.callAgreementWithContext(
            _cfa,
            abi.encodeWithSelector(
                _cfa.createFlow.selector,
                _acceptedToken,
                to,
                flowRate,
                new bytes(0) // placeholder
            ),
            "0x",
            _ctx
        );
    }

    function _getFlowFromContract(address msgSender)
        private
        view
        returns (int96)
    {
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            address(this),
            msgSender
        );
        return outFlowRate;
    }

    function _returnAllBooks(address rentee) private {
        for (uint256 i = 0; i < _renteeRecord[rentee].length; i++) {
            // update flow from contract to the owner
            RenteeRecord memory renteeRecord = _renteeRecord[rentee][i];
            _updateFlowFromContract(
                _rentedBooksRecord[renteeRecord.bookAddress][
                    renteeRecord.copyUid
                ].rentor,
                _rentedBooksRecord[renteeRecord.bookAddress][
                    renteeRecord.copyUid
                ].flowRate.mul(-1)
            );
            // set rentee of edition to 0
            _rentedBooksRecord[renteeRecord.bookAddress][renteeRecord.copyUid]
                .rentee = address(0);
            emit BookReturned(renteeRecord.bookAddress, renteeRecord.copyUid);
        }
        delete _renteeRecord[rentee];
    }

    // External Functions ------------------------------------------------
    // putOnRent
    function putOnRent(
        address bookAddress,
        uint256 copyUid,
        int96 flowRate
    ) external nonReentrant {
        _flowExists(msg.sender);
        Edition edition = Edition(bookAddress);
        require(
            edition.verifyOwnership(msg.sender, copyUid, false),
            "Un-authorized Request"
        );
        require(
            edition.verifyLockedWith(address(this), copyUid),
            "Invalid Request"
        );
        require(
            _rentedBooksRecord[bookAddress][copyUid].rentor != address(0),
            "Already On Rent"
        );
        _rentedBooksRecord[bookAddress][copyUid].rentor = msg.sender;
        _rentedBooksRecord[bookAddress][copyUid].flowRate = flowRate;
        emit BookPutOnRent(bookAddress, copyUid, flowRate);
    }

    // removeFromRent
    function removeFromRent(address bookAddress, uint256 copyUid)
        external
        nonReentrant
    {
        _flowExists(msg.sender);
        require(
            _rentedBooksRecord[bookAddress][copyUid].rentor == msg.sender,
            "Un-authorized Request"
        );
        require(
            _rentedBooksRecord[bookAddress][copyUid].rentee == address(0),
            "Permission Denied"
        );
        delete _rentedBooksRecord[bookAddress][copyUid];
        Edition edition = Edition(bookAddress);
        edition.unlock(copyUid);
        emit BookRemovedFromRent(bookAddress, copyUid);
    }

    // takeOnRent
    function takeOnRent(address bookAddress, uint256 copyUid)
        external
        nonReentrant
    {
        _flowExists(msg.sender);
        RentRecord memory record = _rentedBooksRecord[bookAddress][copyUid];
        require(record.rentor != address(0), "Not Available For Rent");
        require(record.rentee == address(0), "Already Rented");
        require(
            _getFlowFromContract(msg.sender) >= record.flowRate,
            "Insufficient Flow Balance"
        );
        _rentedBooksRecord[bookAddress][copyUid].rentee = msg.sender;
        _renteeRecord[msg.sender].push(RenteeRecord(bookAddress, copyUid));
        _updateFlowFromContract(msg.sender, record.flowRate.mul(-1));
        _updateFlowFromContract(record.rentor, record.flowRate);
        emit BookTakenOnRent(bookAddress, copyUid, msg.sender, record.flowRate);
    }

    // returnOnRent
    function returnBook(address bookAddress, uint256 copyUid)
        external
        nonReentrant
    {
        _flowExists(msg.sender);
        RentRecord memory record = _rentedBooksRecord[bookAddress][copyUid];
        require(record.rentee == msg.sender, "Un-authorized Request");
        _updateFlowFromContract(record.rentor, record.flowRate.mul(-1));
        _rentedBooksRecord[bookAddress][copyUid].rentee = address(0);
        for (uint256 i = 0; i < _renteeRecord[msg.sender].length; i++) {
            if (
                _renteeRecord[msg.sender][i].bookAddress == bookAddress &&
                _renteeRecord[msg.sender][i].copyUid == copyUid
            ) {
                for (
                    uint256 j = i;
                    j < _renteeRecord[msg.sender].length - 1;
                    j++
                ) {
                    _renteeRecord[msg.sender][j] = _renteeRecord[msg.sender][
                        j + 1
                    ];
                }
                delete _renteeRecord[msg.sender][
                    _renteeRecord[msg.sender].length - 1
                ];
                break;
            }
        }
        _updateFlowFromContract(msg.sender, record.flowRate);
        emit BookReturned(bookAddress, copyUid);
    }

    // requestBookUri
    function uri(address bookAddress, uint256 copyUid)
        external
        nonReentrant
        returns (string memory)
    {
        _flowExists(msg.sender);
        RentRecord memory record = _rentedBooksRecord[bookAddress][copyUid];
        require(record.rentor != address(0), "Not Available For Rent");
        require(record.rentee == msg.sender, "Un-authorized Request");
        Edition edition = Edition(bookAddress);
        return edition.uri(copyUid);
    }

    // addToWaitingList
    // function addToWaitingList(address bookAddress, uint256 copyUid)
    //     external
    //     nonReentrant
    // {
    //     _flowExists(msg.sender);
    //     // TODO: emit event
    //     emit AddedToWaitingList(bookAddress, copyUid);
    // }

    // removeFromWaitingList
    // function removeFromWaitingList(address bookAddress, uint256 copyUid)
    //     external
    //     nonReentrant
    // {
    //     _flowExists(msg.sender);
    //     // TODO: emit event
    //     emit RemovedFromWaitingList(bookAddress, copyUid);
    // }

    // function _authorizeUpgrade(
    //     address /*newImplementation*/
    // ) internal view override onlyOwner {}

    // Super Agreement Callbacks -----------------------------------------
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        ISuperfluid.Context memory context = _host.decodeCtx(_ctx);
        (, int96 inFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            context.msgSender,
            address(this)
        );
        _flowBalances[context.msgSender] = inFlowRate;
        newCtx = _createFlowFromAgreement(context.msgSender, inFlowRate, _ctx);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        ISuperfluid.Context memory context = _host.decodeCtx(_ctx);
        (, int96 inFlowRate, , ) = _cfa.getFlow(
            _acceptedToken,
            context.msgSender,
            address(this)
        );
        int96 flowFromContract = _getFlowFromContract(context.msgSender);
        if (
            inFlowRate >= _flowBalances[context.msgSender].sub(flowFromContract)
        ) {
            newCtx = _updateFlowFromContractWithCtx(
                context.msgSender,
                inFlowRate.sub(_flowBalances[context.msgSender]),
                _ctx
            );
        } else {
            newCtx = _deleteFlowFromContract(context.msgSender, _ctx);
            _returnAllBooks(context.msgSender);
            newCtx = _createFlowFromAgreement(
                context.msgSender,
                inFlowRate,
                newCtx
            );
        }
        _flowBalances[context.msgSender] = inFlowRate;
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        ISuperfluid.Context memory context = _host.decodeCtx(_ctx);
        newCtx = _deleteFlowFromContract(context.msgSender, _ctx);
        _returnAllBooks(context.msgSender);
        delete _flowBalances[context.msgSender];
    }
}
// -----------------------------
