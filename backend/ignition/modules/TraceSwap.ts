import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Ignition deployment module for TraceSwap contracts
 * Deploys TenderFactory, AuctionManager, and EscrowVault with immutable references
 * 
 * Note: Due to circular dependencies, we deploy in a specific order:
 * 1. Deploy EscrowVault and AuctionManager with temporary address
 * 2. Deploy TenderFactory with real addresses
 * 3. Use the first deployed contracts (they won't be used, just for address calculation)
 */
const TraceSwapModule = buildModule("TraceSwapModule", (m) => {
    // Get deployer account as fee collector
    const deployer = m.getAccount(0);

    // Calculate future addresses using CREATE2 or deploy in correct order
    // For simplicity, we'll deploy all three at once with proper constructor args

    // First, deploy temporary contracts to get addresses
    const tempEscrow = m.contract("EscrowVault", [
        "0x0000000000000000000000000000000000000001", // placeholder
        deployer
    ], { id: "TempEscrow" });

    const tempAuction = m.contract("AuctionManager", [
        "0x0000000000000000000000000000000000000001" // placeholder
    ], { id: "TempAuction" });

    // Deploy TenderFactory with temp addresses
    const tenderFactory = m.contract("TenderFactory", [
        tempEscrow,
        tempAuction
    ]);

    // Deploy final EscrowVault with correct TenderFactory
    const escrowVault = m.contract("EscrowVault", [
        tenderFactory,
        deployer
    ], {
        id: "EscrowVault",
        after: [tenderFactory]
    });

    // Deploy final AuctionManager with correct TenderFactory
    const auctionManager = m.contract("AuctionManager", [
        tenderFactory
    ], {
        id: "AuctionManager",
        after: [tenderFactory]
    });

    return {
        tenderFactory,
        auctionManager,
        escrowVault,
    };
});

export default TraceSwapModule;
