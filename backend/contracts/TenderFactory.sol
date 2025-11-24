// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    MerkleProof
} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IEscrowVault} from "./interfaces/IEscrowVault.sol";
import {IAuctionManager} from "./interfaces/IAuctionManager.sol";

/**
 * @title TenderFactory
 * @notice Manages the creation of Tenders as NFTs and handles initial collateral locking.
 * @dev Implements ERC721 for Tender representation, AccessControl for role management,
 *      and MerkleProof for buyer whitelisting. Follows KISS, DRY, and SOLID principles.
 */
contract TenderFactory is ERC721, AccessControl {
    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // --- Errors ---
    error UnauthorizedBuyer(address buyer);
    error InvalidAddress();

    // --- Immutable State Variables ---
    address public immutable escrowVault;
    address public immutable auctionManager;

    // --- State Variables ---
    bytes32 public buyerMerkleRoot;
    uint256 private _nextTokenId;

    // --- Events ---
    event TenderCreated(
        uint256 indexed tenderId,
        string ipfsHash,
        address indexed buyer
    );
    event BuyerMerkleRootUpdated(bytes32 indexed newRoot);

    /**
     * @notice Constructor initializes the contract with immutable dependencies
     * @param _escrowVault Address of the EscrowVault contract
     * @param _auctionManager Address of the AuctionManager contract
     */
    constructor(
        address _escrowVault,
        address _auctionManager
    ) ERC721("TraceSwap Tender", "TNDR") {
        if (_escrowVault == address(0) || _auctionManager == address(0)) {
            revert InvalidAddress();
        }

        escrowVault = _escrowVault;
        auctionManager = _auctionManager;

        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Creates a new Tender NFT and starts the auction.
     * @param ipfsHash The IPFS hash of the tender metadata.
     * @param deadline The auction deadline timestamp.
     * @param proof The Merkle proof verifying the caller is a whitelisted buyer.
     */
    function createTender(
        string memory ipfsHash,
        uint256 deadline,
        bytes32[] calldata proof
    ) external payable {
        // Verify whitelist
        if (!_verifyWhitelist(msg.sender, proof)) {
            revert UnauthorizedBuyer(msg.sender);
        }

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Handle collateral if payment is sent
        if (msg.value > 0) {
            IEscrowVault(payable(escrowVault)).deposit{value: msg.value}(
                tokenId
            );
        }

        // Start auction
        IAuctionManager(auctionManager).startAuction(tokenId, deadline);

        emit TenderCreated(tokenId, ipfsHash, msg.sender);
    }

    /**
     * @notice Sets the Merkle Root for buyer whitelist.
     * @param _root The new Merkle Root.
     */
    function setBuyerMerkleRoot(bytes32 _root) external onlyRole(ADMIN_ROLE) {
        buyerMerkleRoot = _root;
        emit BuyerMerkleRootUpdated(_root);
    }

    /**
     * @notice Verifies if an address is whitelisted using Merkle proof
     * @param account The address to verify
     * @param proof The Merkle proof
     * @return bool True if the address is whitelisted
     */
    function _verifyWhitelist(
        address account,
        bytes32[] calldata proof
    ) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(proof, buyerMerkleRoot, leaf);
    }

    /**
     * @dev Required override for AccessControl and ERC721
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
