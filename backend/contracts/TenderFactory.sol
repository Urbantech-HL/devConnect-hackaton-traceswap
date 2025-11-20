// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IEscrowVault} from "./interfaces/IEscrowVault.sol";
import {IAuctionManager} from "./interfaces/IAuctionManager.sol";

contract TenderFactory is ERC721, Ownable {
    // State variables
    bytes32 public buyerMerkleRoot;
    address public escrowVault;
    address public auctionManager;
    uint256 private _nextTokenId;

    // Events
    event TenderCreated(
        uint256 indexed tenderId,
        string ipfsHash,
        address indexed buyer
    );

    constructor() ERC721("TraceSwap Tender", "TNDR") Ownable(msg.sender) {}

    function createTender(
        string memory ipfsHash,
        uint256 deadline,
        bytes32[] calldata proof
    ) external payable {
        // Verify whitelist
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(proof, buyerMerkleRoot, leaf),
            "Not authorized buyer"
        );

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        if (msg.value > 0) {
            require(escrowVault != address(0), "EscrowVault not set");
            IEscrowVault(payable(escrowVault)).deposit{value: msg.value}(tokenId);
        }

        if (auctionManager != address(0)) {
            IAuctionManager(auctionManager).startAuction(tokenId, deadline);
        }

        emit TenderCreated(tokenId, ipfsHash, msg.sender);
    }

    function setEscrowVault(address _escrowVault) external onlyOwner {
        escrowVault = _escrowVault;
    }

    function setAuctionManager(address _manager) external onlyOwner {
        auctionManager = _manager;
    }

    function setBuyerMerkleRoot(bytes32 _root) external onlyOwner {
        buyerMerkleRoot = _root;
    }
}
