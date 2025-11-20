import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { parseEther } from "viem";
import { createMerkleTree, getMerkleRoot, getMerkleProof } from "./MerkleTree.js";

describe("TraceSwap Integration", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();

  it("Should execute full flow", async function () {
    const [owner, buyer, supplier1, supplier2, admin] =
      await viem.getWalletClients();

    // Deploy contracts
    const tenderFactory = await viem.deployContract("TenderFactory", []);
    const auctionManager = await viem.deployContract("AuctionManager", []);
    const escrowVault = await viem.deployContract("EscrowVault", []);

    // Setup relationships
    await tenderFactory.write.setEscrowVault([escrowVault.address]);
    await tenderFactory.write.setAuctionManager([auctionManager.address]);
    await auctionManager.write.setTenderFactory([tenderFactory.address]);
    await escrowVault.write.setTenderFactory([tenderFactory.address]);

    // Configure Merkle roots
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

    // 1. Create Tender
    const ipfsHash = "QmTest";
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour
    const buyerProof = getMerkleProof(buyersTree, buyer.account.address);
    const depositAmount = parseEther("1");

    await tenderFactory.write.createTender([ipfsHash, deadline, buyerProof], {
      account: buyer.account,
      value: depositAmount,
    });

    // Check Tender Created
    const balance = await tenderFactory.read.balanceOf([
      buyer.account.address,
    ]);
    assert.equal(balance, 1n);

    // Check Escrow Deposit
    const deposit = await escrowVault.read.tenderDeposits([0n]);
    assert.equal(deposit, depositAmount);

    // Check Auction Started
    const auction = await auctionManager.read.auctions([0n]);
    const [auctionDeadline, auctionClosed] = auction;
    assert.equal(auctionDeadline, deadline);
    assert.equal(auctionClosed, false);

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

    // Check Bid
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
    );
    assert.equal(bestBidAmount, bidAmount);

    // 3. Close Auction (Simulate time pass)
    await networkHelpers.time.increase(3601);
    await networkHelpers.mine();

    // Perform Upkeep
    const [upkeepNeeded, performData] = await auctionManager.read.checkUpkeep([
      "0x",
    ]);
    assert.equal(upkeepNeeded, true);

    await auctionManager.write.performUpkeep([performData]);

    // Check Winner
    const closedAuction = await auctionManager.read.auctions([0n]);
    const [, closed, winner] = closedAuction;
    assert.equal(closed, true);
    assert.equal(
      winner.toLowerCase(),
      supplier1.account.address.toLowerCase(),
    );

    // 4. Release Funds (Admin)
    const adminProof = getMerkleProof(adminTree, admin.account.address);

    const balanceBefore = await publicClient.getBalance({
      address: supplier1.account.address,
    });

    await escrowVault.write.releaseFunds(
      [0n, supplier1.account.address, adminProof],
      {
        account: admin.account,
      },
    );

    const balanceAfter = await publicClient.getBalance({
      address: supplier1.account.address,
    });

    // Expected payment = 1 ETH - 0.2% fee
    const fee = (depositAmount * 20n) / 10000n;
    const payment = depositAmount - fee;

    assert.equal(balanceAfter - balanceBefore, payment);
  });
});
