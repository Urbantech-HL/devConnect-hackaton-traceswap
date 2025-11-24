// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITenderFactory {
    // Events
    event TenderCreated(
        uint256 indexed tenderId,
        string ipfsHash,
        address indexed buyer
    );

    // Getters
    function buyerMerkleRoot() external view returns (bytes32);

    function escrowVault() external view returns (address);

    function auctionManager() external view returns (address);

    // External functions
    function createTender(
        string memory ipfsHash,
        uint256 deadline,
        bytes32[] calldata proof
    ) external payable;

    function setEscrowVault(address _escrowVault) external;

    function setAuctionManager(address _manager) external;

    function setBuyerMerkleRoot(bytes32 _root) external;
}
