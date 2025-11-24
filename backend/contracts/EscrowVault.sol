// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    MerkleProof
} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title EscrowVault
 * @notice Manages escrow deposits and fund releases for TraceSwap tenders
 * @dev Uses AccessControl for role management, MerkleProof for admin whitelist,
 *      and ReentrancyGuard for security. Follows KISS, DRY, SOLID principles.
 */
contract EscrowVault is AccessControl, ReentrancyGuard {
    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // --- Constants ---
    uint256 public constant FEE_BASIS_POINTS = 20; // 0.2% fee (20/10000)
    uint256 public constant BASIS_POINTS = 10000;

    // --- Immutable State Variables ---
    address public immutable tenderFactory;
    address public immutable feeCollector;

    // --- State Variables ---
    bytes32 public adminMerkleRoot;
    uint256 public totalFeesCollected;

    // Mapping: tenderId => deposited amount
    mapping(uint256 => uint256) public tenderDeposits;

    // Mapping: tenderId => released status
    mapping(uint256 => bool) public tenderReleased;

    // --- Events ---
    event DepositReceived(uint256 indexed tenderId, uint256 amount);
    event FundsReleased(
        uint256 indexed tenderId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );
    event FeesWithdrawn(address indexed collector, uint256 amount);
    event AdminMerkleRootUpdated(bytes32 indexed newRoot);

    // --- Custom errors ---
    error NotAuthorized();
    error InvalidAmount();
    error InvalidAddress();
    error AlreadyReleased();
    error NoFundsToWithdraw();
    error TransferFailed();

    /**
     * @notice Constructor initializes contract with immutable dependencies
     * @param _tenderFactory Address of the TenderFactory contract
     * @param _feeCollector Address that collects platform fees
     */
    constructor(address _tenderFactory, address _feeCollector) {
        if (_tenderFactory == address(0) || _feeCollector == address(0)) {
            revert InvalidAddress();
        }

        tenderFactory = _tenderFactory;
        feeCollector = _feeCollector;

        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, _tenderFactory);
    }

    /**
     * @notice Set the admin merkle root for authorization
     * @param _root New merkle root
     */
    function setAdminMerkleRoot(bytes32 _root) external onlyRole(ADMIN_ROLE) {
        adminMerkleRoot = _root;
        emit AdminMerkleRootUpdated(_root);
    }

    /**
     * @notice Deposit funds for a tender (called by TenderFactory)
     * @param tenderId ID of the tender
     */
    function deposit(uint256 tenderId) external payable onlyRole(FACTORY_ROLE) {
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
        if (!_verifyWhitelist(msg.sender, proof)) {
            revert NotAuthorized();
        }

        // Check if already released
        if (tenderReleased[tenderId]) revert AlreadyReleased();

        uint256 depositAmount = tenderDeposits[tenderId];
        if (depositAmount == 0) revert InvalidAmount();

        // Mark as released (Checks-Effects-Interactions pattern)
        tenderReleased[tenderId] = true;

        // Calculate fee and payment
        uint256 fee = (depositAmount * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 payment = depositAmount - fee;

        // Update fee tracking
        totalFeesCollected += fee;

        // Transfer funds to recipient
        _safeTransfer(recipient, payment);

        emit FundsReleased(tenderId, recipient, payment, fee);
    }

    /**
     * @notice Withdraw collected fees (only fee collector or admin)
     */
    function withdrawFees() external nonReentrant {
        if (!hasRole(ADMIN_ROLE, msg.sender) && msg.sender != feeCollector) {
            revert NotAuthorized();
        }

        uint256 feesToWithdraw = totalFeesCollected;
        if (feesToWithdraw == 0) revert NoFundsToWithdraw();

        // Reset fees before transfer (Checks-Effects-Interactions pattern)
        totalFeesCollected = 0;

        _safeTransfer(feeCollector, feesToWithdraw);

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
     * @notice Internal function to safely transfer ETH
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransfer(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
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
        return MerkleProof.verify(proof, adminMerkleRoot, leaf);
    }

    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable {}
}
