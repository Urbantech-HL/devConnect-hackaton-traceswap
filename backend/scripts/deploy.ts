import hre from "hardhat";

/**
 * Simple deployment script for TraceSwap contracts
 * Deploys and configures all three core contracts
 */
async function main() {
    console.log("🚀 Starting TraceSwap deployment...\n");

    // Deploy EscrowVault
    console.log("📦 Deploying EscrowVault...");
    const escrowVault = await hre.viem.deployContract("EscrowVault", []);
    console.log("✅ EscrowVault deployed at:", escrowVault.address);

    // Deploy AuctionManager
    console.log("\n📦 Deploying AuctionManager...");
    const auctionManager = await hre.viem.deployContract("AuctionManager", []);
    console.log("✅ AuctionManager deployed at:", auctionManager.address);

    // Deploy TenderFactory
    console.log("\n📦 Deploying TenderFactory...");
    const tenderFactory = await hre.viem.deployContract("TenderFactory", []);
    console.log("✅ TenderFactory deployed at:", tenderFactory.address);

    // Configure TenderFactory
    console.log("\n⚙️  Configuring TenderFactory...");
    await tenderFactory.write.setEscrowVault([escrowVault.address]);
    console.log("  - Set EscrowVault address");

    await tenderFactory.write.setAuctionManager([auctionManager.address]);
    console.log("  - Set AuctionManager address");

    // Configure AuctionManager
    console.log("\n⚙️  Configuring AuctionManager...");
    await auctionManager.write.setTenderFactory([tenderFactory.address]);
    console.log("  - Set TenderFactory address");

    // Summary
    console.log("\n✨ Deployment complete!\n");
    console.log("📋 Contract Addresses:");
    console.log("  TenderFactory:  ", tenderFactory.address);
    console.log("  AuctionManager: ", auctionManager.address);
    console.log("  EscrowVault:    ", escrowVault.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
