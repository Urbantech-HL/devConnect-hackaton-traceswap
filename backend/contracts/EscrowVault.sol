// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title EscrowVault
 * @notice Manages escrow deposits and fund releases for TraceSwap tenders
 * @dev Uses MerkleProof for admin whitelist and ReentrancyGuard for security
 */
contract EscrowVault is Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant FEE_BASIS_POINTS = 20; // 0.2% fee (20/10000)
    uint256 public constant BASIS_POINTS = 10000;

    // State variables
    bytes32 public adminMerkleRoot;
    address public tenderFactory;
    address public feeCollector;
    uint256 public totalFeesCollected;

    // Mapping: tenderId => deposited amount
    mapping(uint256 => uint256) public tenderDeposits;

    // Mapping: tenderId => released status
    mapping(uint256 => bool) public tenderReleased;

    // Events
    event DepositReceived(uint256 indexed tenderId, uint256 amount);
    event FundsReleased(
        uint256 indexed tenderId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );
    event FeesWithdrawn(address indexed collector, uint256 amount);
    event AdminMerkleRootUpdated(bytes32 newRoot);
    event FeeCollectorUpdated(address newCollector);

    // Custom errors
    error NotAuthorized();
    error NotFactory();
    error InvalidAmount();
    error AlreadyReleased();
    error NoFundsToWithdraw();
    error TransferFailed();

    /**
     * @notice Constructor initializes contract with owner
     */
    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    /**
     * @notice Modifier to restrict access to tender factory only
     */
    modifier onlyFactory() {
        if (msg.sender != tenderFactory) revert NotFactory();
        _;
    }

    /**
     * @notice Set the tender factory address
     * @param _factory Address of the TenderFactory contract
     */
    function setTenderFactory(address _factory) external onlyOwner {
        tenderFactory = _factory;
    }

    /**
     * @notice Set the admin merkle root for authorization
     * @param _root New merkle root
     */
    function setAdminMerkleRoot(bytes32 _root) external onlyOwner {
        adminMerkleRoot = _root;
        emit AdminMerkleRootUpdated(_root);
    }

    /**
     * @notice Set the fee collector address
     * @param _collector Address that collects platform fees
     */
    function setFeeCollector(address _collector) external onlyOwner {
        feeCollector = _collector;
        emit FeeCollectorUpdated(_collector);
    }

    /**
     * @notice Deposit funds for a tender (called by TenderFactory)
     * @param tenderId ID of the tender
     */
    function deposit(uint256 tenderId) external payable onlyFactory {
        if (msg.value == 0) revert InvalidAmount();

        tenderDeposits[tenderId] += msg.value;
        emit DepositReceived(tenderId, msg.value);
    }

    /**
     * @notice Release funds to supplier after successful delivery
     * @param tenderId ID of the tender
     * @param recipient Address of the supplier to receive funds
     * @param proof Merkle proof for admin authorization
     */
    function releaseFunds(
        uint256 tenderId,
        address recipient,
        bytes32[] calldata proof
    ) external nonReentrant {
        // Verify admin authorization
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(proof, adminMerkleRoot, leaf)) {
            revert NotAuthorized();
        }

        // Check if already released
        if (tenderReleased[tenderId]) revert AlreadyReleased();

        uint256 depositAmount = tenderDeposits[tenderId];
        if (depositAmount == 0) revert InvalidAmount();

        // Mark as released
        tenderReleased[tenderId] = true;

        // Calculate fee and payment
        uint256 fee = (depositAmount * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 payment = depositAmount - fee;

        // Update fee tracking
        totalFeesCollected += fee;

        // Transfer funds to recipient
        (bool success, ) = recipient.call{value: payment}("");
        if (!success) revert TransferFailed();

        emit FundsReleased(tenderId, recipient, payment, fee);
    }

    /**
     * @notice Withdraw collected fees (only fee collector)
     */
    function withdrawFees() external nonReentrant {
        if (msg.sender != feeCollector && msg.sender != owner()) {
            revert NotAuthorized();
        }

        uint256 feesToWithdraw = totalFeesCollected;
        if (feesToWithdraw == 0) revert NoFundsToWithdraw();

        totalFeesCollected = 0;

        (bool success, ) = feeCollector.call{value: feesToWithdraw}("");
        if (!success) revert TransferFailed();

        emit FeesWithdrawn(feeCollector, feesToWithdraw);
    }

    /**
     * @notice Get deposit amount for a tender
     * @param tenderId ID of the tender
     * @return Deposited amount
     */
    function getDeposit(uint256 tenderId) external view returns (uint256) {
        return tenderDeposits[tenderId];
    }

    /**
     * @notice Check if tender funds have been released
     * @param tenderId ID of the tender
     * @return Release status
     */
    function isReleased(uint256 tenderId) external view returns (bool) {
        return tenderReleased[tenderId];
    }

    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable {}
}
