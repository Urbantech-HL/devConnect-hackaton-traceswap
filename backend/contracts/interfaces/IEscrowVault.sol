// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEscrowVault {
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

    // Errors
    error NotAuthorized();
    error NotFactory();
    error InvalidAmount();
    error AlreadyReleased();
    error NoFundsToWithdraw();
    error TransferFailed();

    // Getters
    function FEE_BASIS_POINTS() external view returns (uint256);

    function BASIS_POINTS() external view returns (uint256);

    function adminMerkleRoot() external view returns (bytes32);

    function tenderFactory() external view returns (address);

    function feeCollector() external view returns (address);

    function totalFeesCollected() external view returns (uint256);

    function tenderDeposits(uint256 tenderId) external view returns (uint256);

    function tenderReleased(uint256 tenderId) external view returns (bool);

    // External functions
    function setTenderFactory(address _factory) external;

    function setAdminMerkleRoot(bytes32 _root) external;

    function setFeeCollector(address _collector) external;

    function deposit(uint256 tenderId) external payable;

    function releaseFunds(
        uint256 tenderId,
        address recipient,
        bytes32[] calldata proof
    ) external;

    function withdrawFees() external;

    function getDeposit(uint256 tenderId) external view returns (uint256);

    function isReleased(uint256 tenderId) external view returns (bool);

    // Receive function
    receive() external payable;
}
