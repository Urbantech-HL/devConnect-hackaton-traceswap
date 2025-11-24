// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAuctionManager {
    // Events
    event BidSubmitted(
        uint256 indexed tenderId,
        address indexed supplier,
        uint256 amount
    );

    event AuctionStarted(uint256 indexed tenderId, uint256 deadline);

    event AuctionClosed(
        uint256 indexed tenderId,
        address winner,
        uint256 amount
    );

    // Getters
    function supplierMerkleRoot() external view returns (bytes32);

    function tenderFactory() external view returns (address);

    function tenderBids(
        uint256 tenderId,
        uint256 index
    )
        external
        view
        returns (
            uint256 amount,
            string memory certsUri,
            address supplier,
            uint256 timestamp
        );

    function auctions(
        uint256 tenderId
    )
        external
        view
        returns (
            uint256 deadline,
            bool closed,
            address winner,
            uint256 winningBidAmount,
            address bestBidder,
            uint256 bestBidAmount
        );

    function activeTenders(uint256 index) external view returns (uint256);

    // External functions
    function setTenderFactory(address _factory) external;

    function startAuction(uint256 tenderId, uint256 deadline) external;

    function submitBid(
        uint256 tenderId,
        uint256 amount,
        string memory certsUri,
        bytes32[] calldata proof
    ) external;

    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;

    function setSupplierMerkleRoot(bytes32 _root) external;
}
