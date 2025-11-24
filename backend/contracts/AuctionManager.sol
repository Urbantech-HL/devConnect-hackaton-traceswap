// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {
    MerkleProof
} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title AuctionManager
 * @notice Manages the bidding process for Tenders and handles automatic closure via Chainlink Automation.
 * @dev Implements Chainlink AutomationCompatibleInterface for `checkUpkeep` and `performUpkeep`.
 *      Uses AccessControl for role-based permissions and follows KISS, DRY, SOLID principles.
 */
contract AuctionManager is AccessControl, AutomationCompatibleInterface {
    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // --- Errors ---
    error AuctionAlreadyClosed();
    error AuctionEnded();
    error UnauthorizedSupplier(address supplier);
    error InvalidTenderId();

    // --- Immutable State Variables ---
    address public immutable tenderFactory;

    // --- State Variables ---
    bytes32 public supplierMerkleRoot;

    struct Bid {
        uint256 amount;
        string certsUri;
        address supplier;
        uint256 timestamp;
    }

    struct Auction {
        uint256 deadline;
        bool closed;
        address winner;
        uint256 winningBidAmount;
        address bestBidder;
        uint256 bestBidAmount;
    }

    mapping(uint256 => Bid[]) public tenderBids;
    mapping(uint256 => Auction) public auctions;
    uint256[] public activeTenders;

    // --- Events ---
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
    event SupplierMerkleRootUpdated(bytes32 indexed newRoot);

    /**
     * @notice Constructor initializes the contract with immutable tenderFactory
     * @param _tenderFactory Address of the TenderFactory contract
     */
    constructor(address _tenderFactory) {
        if (_tenderFactory == address(0)) revert InvalidTenderId();

        tenderFactory = _tenderFactory;

        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, _tenderFactory);
    }

    /**
     * @notice Starts an auction for a specific tender.
     * @dev Called only by TenderFactory.
     * @param tenderId The ID of the tender.
     * @param deadline The timestamp when the auction ends.
     */
    function startAuction(
        uint256 tenderId,
        uint256 deadline
    ) external onlyRole(FACTORY_ROLE) {
        auctions[tenderId] = Auction({
            deadline: deadline,
            closed: false,
            winner: address(0),
            winningBidAmount: 0,
            bestBidder: address(0),
            bestBidAmount: 0
        });
        activeTenders.push(tenderId);
        emit AuctionStarted(tenderId, deadline);
    }

    /**
     * @notice Submits a bid for a tender.
     * @param tenderId The ID of the tender.
     * @param amount The bid amount (price).
     * @param certsUri IPFS URI for certifications.
     * @param proof Merkle proof for supplier whitelist.
     */
    function submitBid(
        uint256 tenderId,
        uint256 amount,
        string memory certsUri,
        bytes32[] calldata proof
    ) external {
        Auction storage auction = auctions[tenderId];
        if (auction.closed) revert AuctionAlreadyClosed();
        if (block.timestamp >= auction.deadline) revert AuctionEnded();

        // Verify whitelist
        if (!_verifyWhitelist(msg.sender, proof)) {
            revert UnauthorizedSupplier(msg.sender);
        }

        tenderBids[tenderId].push(
            Bid({
                amount: amount,
                certsUri: certsUri,
                supplier: msg.sender,
                timestamp: block.timestamp
            })
        );

        // Update best bid (Lowest Price strategy)
        if (amount < auction.bestBidAmount || auction.bestBidAmount == 0) {
            auction.bestBidAmount = amount;
            auction.bestBidder = msg.sender;
        }

        emit BidSubmitted(tenderId, msg.sender, amount);
    }

    /**
     * @notice Checks if any auctions need to be closed.
     * @return upkeepNeeded True if there are auctions to close.
     * @return performData Encoded array of tenderIds to close.
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256[] memory tendersToClose = new uint256[](activeTenders.length);
        uint256 count = 0;

        uint256 length = activeTenders.length;
        for (uint256 i = 0; i < length; ) {
            uint256 tenderId = activeTenders[i];
            Auction storage auction = auctions[tenderId];

            if (block.timestamp > auction.deadline && !auction.closed) {
                tendersToClose[count] = tenderId;
                unchecked {
                    ++count;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (count > 0) {
            // Resize array
            uint256[] memory result = new uint256[](count);
            for (uint256 i = 0; i < count; ) {
                result[i] = tendersToClose[i];
                unchecked {
                    ++i;
                }
            }
            return (true, abi.encode(result));
        }

        return (false, "");
    }

    /**
     * @notice Closes auctions that have passed their deadline.
     * @param performData Encoded array of tenderIds to close.
     */
    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory tendersToClose = abi.decode(performData, (uint256[]));

        uint256 length = tendersToClose.length;
        for (uint256 i = 0; i < length; ) {
            _closeAuction(tendersToClose[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets the Merkle Root for supplier whitelist.
     * @param _root The new Merkle Root.
     */
    function setSupplierMerkleRoot(
        bytes32 _root
    ) external onlyRole(ADMIN_ROLE) {
        supplierMerkleRoot = _root;
        emit SupplierMerkleRootUpdated(_root);
    }

    /**
     * @notice Internal function to close a single auction
     * @param tenderId The ID of the tender to close
     */
    function _closeAuction(uint256 tenderId) private {
        Auction storage auction = auctions[tenderId];

        if (block.timestamp > auction.deadline && !auction.closed) {
            auction.closed = true;
            auction.winner = auction.bestBidder;
            auction.winningBidAmount = auction.bestBidAmount;

            // Remove from activeTenders (swap and pop)
            _removeActiveTender(tenderId);

            emit AuctionClosed(
                tenderId,
                auction.winner,
                auction.winningBidAmount
            );
        }
    }

    /**
     * @notice Internal function to remove a tender from activeTenders array
     * @param tenderId The ID of the tender to remove
     */
    function _removeActiveTender(uint256 tenderId) private {
        uint256 length = activeTenders.length;
        for (uint256 j = 0; j < length; ) {
            if (activeTenders[j] == tenderId) {
                activeTenders[j] = activeTenders[length - 1];
                activeTenders.pop();
                break;
            }
            unchecked {
                ++j;
            }
        }
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
        return MerkleProof.verify(proof, supplierMerkleRoot, leaf);
    }
}
