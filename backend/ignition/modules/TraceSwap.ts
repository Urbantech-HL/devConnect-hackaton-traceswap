import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Ignition deployment module for TraceSwap contracts
 * Deploys and configures TenderFactory, AuctionManager, and EscrowVault
 */
const TraceSwapModule = buildModule("TraceSwapModule", (m) => {
    // Deploy EscrowVault
    const escrowVault = m.contract("EscrowVault", []);

    // Deploy AuctionManager
    const auctionManager = m.contract("AuctionManager", []);

    // Deploy TenderFactory
    const tenderFactory = m.contract("TenderFactory", []);

    // Configure TenderFactory
    m.call(tenderFactory, "setEscrowVault", [escrowVault]);
    m.call(tenderFactory, "setAuctionManager", [auctionManager]);

    // Configure AuctionManager
    m.call(auctionManager, "setTenderFactory", [tenderFactory]);

    return {
        tenderFactory,
        auctionManager,
        escrowVault,
    };
});

export default TraceSwapModule;
