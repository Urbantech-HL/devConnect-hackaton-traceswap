// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AuctionManager is Ownable, AutomationCompatibleInterface {
    // State variables
    bytes32 public supplierMerkleRoot;
    address public tenderFactory;

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

    constructor() Ownable(msg.sender) {}

    modifier onlyFactory() {
        require(msg.sender == tenderFactory, "Only factory");
        _;
    }

    function setTenderFactory(address _factory) external onlyOwner {
        tenderFactory = _factory;
    }

    function startAuction(
        uint256 tenderId,
        uint256 deadline
    ) external onlyFactory {
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

    function submitBid(
        uint256 tenderId,
        uint256 amount,
        string memory certsUri,
        bytes32[] calldata proof
    ) external {
        Auction storage auction = auctions[tenderId];
        require(!auction.closed, "Auction closed");
        require(block.timestamp < auction.deadline, "Auction ended");

        // Verify whitelist
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(proof, supplierMerkleRoot, leaf),
            "Not authorized supplier"
        );

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

        for (uint256 i = 0; i < activeTenders.length; i++) {
            uint256 tenderId = activeTenders[i];
            if (
                block.timestamp > auctions[tenderId].deadline &&
                !auctions[tenderId].closed
            ) {
                tendersToClose[count] = tenderId;
                count++;
            }
        }

        if (count > 0) {
            // Resize array
            uint256[] memory result = new uint256[](count);
            for (uint256 i = 0; i < count; i++) {
                result[i] = tendersToClose[i];
            }
            return (true, abi.encode(result));
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory tendersToClose = abi.decode(performData, (uint256[]));

        for (uint256 i = 0; i < tendersToClose.length; i++) {
            uint256 tenderId = tendersToClose[i];
            Auction storage auction = auctions[tenderId];

            if (block.timestamp > auction.deadline && !auction.closed) {
                auction.closed = true;
                auction.winner = auction.bestBidder;
                auction.winningBidAmount = auction.bestBidAmount;

                // Remove from activeTenders (swap and pop)
                for (uint256 j = 0; j < activeTenders.length; j++) {
                    if (activeTenders[j] == tenderId) {
                        activeTenders[j] = activeTenders[
                            activeTenders.length - 1
                        ];
                        activeTenders.pop();
                        break;
                    }
                }

                emit AuctionClosed(
                    tenderId,
                    auction.winner,
                    auction.winningBidAmount
                );
            }
        }
    }

    function setSupplierMerkleRoot(bytes32 _root) external onlyOwner {
        supplierMerkleRoot = _root;
    }
}
