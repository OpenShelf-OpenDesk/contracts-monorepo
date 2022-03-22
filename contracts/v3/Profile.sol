// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./contracts/ReentrancyGuard.sol";

contract Profile is ReentrancyGuard {
    event ReaderProfileUpdated(
        address indexed readerAddress,
        string profileMetadataUri
    );

    event ContributorProfileUpdated(
        address indexed contributorAddress,
        string profileMetadataUri
    );

    function updateReaderProfile(string memory profileMetadataUri) external {
        emit ReaderProfileUpdated(msg.sender, profileMetadataUri);
    }

    function updateContributorProfile(string memory profileMetadataUri)
        external
    {
        emit ContributorProfileUpdated(msg.sender, profileMetadataUri);
    }
}
