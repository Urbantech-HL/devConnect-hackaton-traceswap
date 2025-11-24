import hre, { network } from "hardhat";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { verifyContract } from "@nomicfoundation/hardhat-verify/verify";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
    // 1. Setup Connection & Wallets
    // -----------------------------
    const { viem, networkName } = await network.connect();

    console.log(`🚀 Starting TraceSwap deployment on network: ${networkName}`);

    const publicClient = await viem.getPublicClient();
    const walletClients = await viem.getWalletClients();
    const [owner] = walletClients;

    if (!owner) {
        throw new Error("No owner account found! Ensure your hardhat.config.ts has accounts configured.");
    }

    console.log(`\n👤 Deploying with account: ${owner.account.address}`);
    const balance = await publicClient.getBalance({ address: owner.account.address });
    console.log(`💰 Balance: ${balance.toString()} wei`);

    // 2. Deploy Contracts
    // -------------------
    console.log("\n📦 Deploying Contracts...");

    // Deploy EscrowVault and AuctionManager first with placeholder addresses
    // Then deploy TenderFactory, then redeploy EscrowVault and AuctionManager with correct address

    // Approach: Deploy in sequence with temporary addresses, then use the final ones
    console.log("  - Deploying temporary EscrowVault...");
    const tempEscrow = await viem.deployContract("EscrowVault", [
        "0x0000000000000000000000000000000000000001", // placeholder
        owner.account.address // fee collector
    ]);

    console.log("  - Deploying temporary AuctionManager...");
    const tempAuction = await viem.deployContract("AuctionManager", [
        "0x0000000000000000000000000000000000000001" as `0x${string}` // placeholder
    ]);

    console.log("  - Deploying TenderFactory...");
    const tenderFactory = await viem.deployContract("TenderFactory", [
        tempEscrow.address,
        tempAuction.address
    ]);
    console.log(`✅ TenderFactory deployed at: ${tenderFactory.address}`);

    // Deploy final EscrowVault with correct TenderFactory
    console.log("  - Deploying final EscrowVault...");
    const escrowVault = await viem.deployContract("EscrowVault", [
        tenderFactory.address as `0x${string}`,
        owner.account.address as `0x${string}` // fee collector
    ]);
    console.log(`✅ EscrowVault deployed at: ${escrowVault.address}`);

    // Deploy final AuctionManager with correct TenderFactory
    console.log("  - Deploying final AuctionManager...");
    const auctionManager = await viem.deployContract("AuctionManager", [
        tenderFactory.address as `0x${string}`
    ]);
    console.log(`✅ AuctionManager deployed at: ${auctionManager.address}`);

    // 3. Note: No configuration needed as contracts are immutable
    // ----------------------------------------------------------
    console.log("\n✅ All contracts deployed with immutable references!");

    // 4. Configure Merkle Roots (Whitelist)
    // -------------------------------------
    console.log("\n🔐 Configuring Whitelists (Merkle Roots)...");
    const rootsPath = path.join(__dirname, "merkle-roots.json");

    if (fs.existsSync(rootsPath)) {
        const roots = JSON.parse(fs.readFileSync(rootsPath, "utf8"));

        if (roots.buyerMerkleRoot) {
            console.log("  - Setting Buyer Merkle Root...");
            await tenderFactory.write.setBuyerMerkleRoot([roots.buyerMerkleRoot]);
        }

        if (roots.supplierMerkleRoot) {
            console.log("  - Setting Supplier Merkle Root...");
            await auctionManager.write.setSupplierMerkleRoot([roots.supplierMerkleRoot]);
        }

        if (roots.adminMerkleRoot) {
            console.log("  - Setting Admin Merkle Root...");
            await escrowVault.write.setAdminMerkleRoot([roots.adminMerkleRoot]);
        }
    } else {
        console.warn("⚠️  merkle-roots.json not found. Skipping whitelist configuration.");
    }

    // 5. Save Deployment Info
    // -----------------------
    console.log("\n💾 Saving deployment info...");
    const deploymentInfo = {
        network: networkName,
        timestamp: new Date().toISOString(),
        contracts: {
            TenderFactory: tenderFactory.address,
            AuctionManager: auctionManager.address,
            EscrowVault: escrowVault.address,
        },
    };

    const deploymentPath = path.join(__dirname, "../deployed-addresses.json");
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`  - Saved to ${deploymentPath}`);

    // 5.1 Export to Frontend
    // ----------------------
    console.log("\n📤 Exporting to Frontend...");
    const frontendPath = path.join(__dirname, "../../frontend/contractInfo");
    if (!fs.existsSync(frontendPath)) {
        fs.mkdirSync(frontendPath, { recursive: true });
    }

    const getAbi = (contractName: string) => {
        const artifactPath = path.join(__dirname, `../artifacts/contracts/${contractName}.sol/${contractName}.json`);
        if (fs.existsSync(artifactPath)) {
            const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
            return artifact.abi;
        }
        return [];
    };

    const chainId = await publicClient.getChainId();

    const contractInfoContent = `export const CONTRACT_INFO = {
    network: "${networkName}",
    chainId: ${chainId},
    contracts: {
        TenderFactory: {
            address: "${tenderFactory.address}",
            abi: ${JSON.stringify(getAbi("TenderFactory"))} as const
        },
        AuctionManager: {
            address: "${auctionManager.address}",
            abi: ${JSON.stringify(getAbi("AuctionManager"))} as const
        },
        EscrowVault: {
            address: "${escrowVault.address}",
            abi: ${JSON.stringify(getAbi("EscrowVault"))} as const
        }
    }
} as const;
`;

    fs.writeFileSync(path.join(frontendPath, "contractInfo.tsx"), contractInfoContent);
    console.log(`  - Saved to ${path.join(frontendPath, "contractInfo.tsx")}`);

    // 6. Verify Contracts (if on a live network)
    // ------------------------------------------
    if (networkName !== "hardhat" && networkName !== "localhost" && networkName !== "hardhatMainnet") {
        console.log("\n🔍 Verifying contracts on Etherscan/Polygonscan...");
        console.log("Waiting 30 seconds for block confirmations to ensure indexing...");
        await new Promise((resolve) => setTimeout(resolve, 30000));

        const verify = async (name: string, address: string, args: any[] = []) => {
            try {
                console.log(`  - Verifying ${name}...`);
                await verifyContract({
                    address: address,
                    constructorArgs: args,
                }, hre);
                console.log(`    ✅ ${name} verified!`);
            } catch (e: any) {
                if (e.message.toLowerCase().includes("already verified")) {
                    console.log(`    ✅ ${name} already verified!`);
                } else {
                    console.log(`    ❌ ${name} verification failed: ${e.message}`);
                }
            }
        };

        await verify("EscrowVault", escrowVault.address, [tenderFactory.address, owner.account.address]);
        await verify("AuctionManager", auctionManager.address, [tenderFactory.address]);
        await verify("TenderFactory", tenderFactory.address, [escrowVault.address, auctionManager.address]);
    } else {
        console.log(`\nℹ️  Skipping verification on network: ${networkName}`);
    }

    console.log("\n✨ Deployment complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
