import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { parseEther, keccak256, toHex } from "viem";
import { createMerkleTree, getMerkleRoot, getMerkleProof } from "./MerkleTree.js";

describe("TraceSwap Integration", async function () {
    const { viem, networkHelpers } = await network.connect();

    /**
     * Deployment fixture that handles the circular dependency properly
     * and configures all necessary roles and permissions
     */
    async function deployTraceSwapFixture() {
        const [owner, buyer, supplier1, supplier2, admin] =
            await viem.getWalletClients();

        // Step 1: Deploy contracts with temporary/mock addresses to handle circular dependency
        const mockAddress = "0x0000000000000000000000000000000000000001" as `0x${string}`;

        // Deploy EscrowVault with mock TenderFactory address
        const escrowVault = await viem.deployContract("EscrowVault", [
            mockAddress,
            owner.account.address as `0x${string}`
        ]);

        // Deploy AuctionManager with mock TenderFactory address
        const auctionManager = await viem.deployContract("AuctionManager", [
            mockAddress
        ]);

        // Deploy TenderFactory with real EscrowVault and AuctionManager addresses
        const tenderFactory = await viem.deployContract("TenderFactory", [
            escrowVault.address as `0x${string}`,
            auctionManager.address as `0x${string}`
        ]);

        // Step 2: Grant FACTORY_ROLE to TenderFactory in AuctionManager and EscrowVault
        // This is CRITICAL - without this, TenderFactory cannot call startAuction() or deposit()
        const FACTORY_ROLE = keccak256(toHex("FACTORY_ROLE"));
        await auctionManager.write.grantRole([
            FACTORY_ROLE,
            tenderFactory.address as `0x${string}`
        ]);
        await escrowVault.write.grantRole([
            FACTORY_ROLE,
            tenderFactory.address as `0x${string}`
        ]);

        // Step 3: Configure Merkle roots for whitelisting
        const adminTree = createMerkleTree([admin.account.address]);
        await escrowVault.write.setAdminMerkleRoot([getMerkleRoot(adminTree)]);

        const buyersTree = createMerkleTree([buyer.account.address]);
        const suppliersTree = createMerkleTree([
            supplier1.account.address,
            supplier2.account.address,
        ]);

        await tenderFactory.write.setBuyerMerkleRoot([getMerkleRoot(buyersTree)]);
        await auctionManager.write.setSupplierMerkleRoot([
            getMerkleRoot(suppliersTree),
        ]);

        return {
            tenderFactory,
            auctionManager,
            escrowVault,
            owner,
            buyer,
            supplier1,
            supplier2,
            admin,
            buyersTree,
            suppliersTree,
        };
    }

    it("Should execute full flow (simplified without escrow)", async function () {
        const {
            tenderFactory,
            auctionManager,
            buyer,
            supplier1,
            buyersTree,
            suppliersTree,
        } = await networkHelpers.loadFixture(deployTraceSwapFixture);

        // 1. Create Tender
        const ipfsHash = "QmTest";
        const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now
        const buyerProof = getMerkleProof(buyersTree, buyer.account.address);

        // Create tender WITHOUT value (to avoid escrow dependency in this test)
        await tenderFactory.write.createTender([ipfsHash, deadline, buyerProof], {
            account: buyer.account,
        });

        // Verify Tender Created
        const balance = await tenderFactory.read.balanceOf([
            buyer.account.address,
        ]);
        assert.equal(balance, 1n, "Buyer should own 1 tender NFT");

        // Verify Auction Started
        const auction = await auctionManager.read.auctions([0n]);
        const [auctionDeadline, auctionClosed] = auction;
        assert.equal(auctionDeadline, deadline, "Auction deadline should match");
        assert.equal(auctionClosed, false, "Auction should be open");

        // 2. Submit Bid
        const bidAmount = parseEther("0.8");
        const certsUri = "QmCerts";
        const supplierProof = getMerkleProof(
            suppliersTree,
            supplier1.account.address,
        );

        await auctionManager.write.submitBid(
            [0n, bidAmount, certsUri, supplierProof],
            {
                account: supplier1.account,
            },
        );

        // Verify Bid Submitted
        const updatedAuction = await auctionManager.read.auctions([0n]);
        const [
            ,
            ,
            ,
            ,
            bestBidder,
            bestBidAmount,
        ] = updatedAuction;
        assert.equal(
            bestBidder.toLowerCase(),
            supplier1.account.address.toLowerCase(),
            "Best bidder should be supplier1"
        );
        assert.equal(bestBidAmount, bidAmount, "Best bid amount should match");

        // 3. Close Auction (Simulate time passing)
        await networkHelpers.time.increase(3601); // Move forward 1 hour + 1 second
        await networkHelpers.mine(); // Mine a new block

        // Check if upkeep is needed
        const [upkeepNeeded, performData] = await auctionManager.read.checkUpkeep([
            "0x",
        ]);
        assert.equal(upkeepNeeded, true, "Upkeep should be needed after deadline");

        // Perform upkeep to close the auction
        await auctionManager.write.performUpkeep([performData]);

        // Verify Auction Closed and Winner Set
        const closedAuction = await auctionManager.read.auctions([0n]);
        const [, closed, winner] = closedAuction;
        assert.equal(closed, true, "Auction should be closed");
        assert.equal(
            winner.toLowerCase(),
            supplier1.account.address.toLowerCase(),
            "Winner should be supplier1"
        );

        console.log("✅ Integration test passed successfully!");
        console.log("   - Tender created and NFT minted");
        console.log("   - Auction started automatically");
        console.log("   - Bid submitted and tracked");
        console.log("   - Auction closed via Chainlink Automation simulation");
        console.log("   - Winner determined correctly");
    });

    it("Should handle multiple bids and select lowest price", async function () {
        const {
            tenderFactory,
            auctionManager,
            buyer,
            supplier1,
            supplier2,
            buyersTree,
            suppliersTree,
        } = await networkHelpers.loadFixture(deployTraceSwapFixture);

        // Create Tender
        const ipfsHash = "QmTest2";
        const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
        const buyerProof = getMerkleProof(buyersTree, buyer.account.address);

        await tenderFactory.write.createTender([ipfsHash, deadline, buyerProof], {
            account: buyer.account,
        });

        // Submit first bid (higher price)
        const bid1Amount = parseEther("1.0");
        const supplier1Proof = getMerkleProof(suppliersTree, supplier1.account.address);

        await auctionManager.write.submitBid(
            [0n, bid1Amount, "QmCerts1", supplier1Proof],
            {
                account: supplier1.account,
            },
        );

        // Submit second bid (lower price - should win)
        const bid2Amount = parseEther("0.7");
        const supplier2Proof = getMerkleProof(suppliersTree, supplier2.account.address);

        await auctionManager.write.submitBid(
            [0n, bid2Amount, "QmCerts2", supplier2Proof],
            {
                account: supplier2.account,
            },
        );

        // Verify best bid is the lowest
        const auction = await auctionManager.read.auctions([0n]);
        const [, , , , bestBidder, bestBidAmount] = auction;

        assert.equal(
            bestBidder.toLowerCase(),
            supplier2.account.address.toLowerCase(),
            "Best bidder should be supplier2 with lower price"
        );
        assert.equal(bestBidAmount, bid2Amount, "Best bid should be the lowest amount");

        // Close auction
        await networkHelpers.time.increase(3601);
        await networkHelpers.mine();

        const [upkeepNeeded, performData] = await auctionManager.read.checkUpkeep(["0x"]);
        await auctionManager.write.performUpkeep([performData]);

        // Verify winner
        const closedAuction = await auctionManager.read.auctions([0n]);
        const [, closed, winner] = closedAuction;

        assert.equal(closed, true, "Auction should be closed");
        assert.equal(
            winner.toLowerCase(),
            supplier2.account.address.toLowerCase(),
            "Winner should be supplier2 with lowest bid"
        );

        console.log("✅ Multiple bid test passed successfully!");
        console.log("   - Lowest price bid wins as expected");
    });
});
