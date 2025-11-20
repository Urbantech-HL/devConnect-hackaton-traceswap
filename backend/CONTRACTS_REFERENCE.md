# TraceSwap Smart Contracts - Quick Reference

## Contract Addresses (After Deployment)

| Contract | Address | Purpose |
|----------|---------|---------|
| TenderFactory | TBD | Mints Tender NFTs |
| AuctionManager | TBD | Manages bidding & awards |
| EscrowVault | TBD | Holds & releases funds |

## Key Functions

### TenderFactory

#### `createTender(string ipfsHash, uint256 deadline, bytes32[] proof)`
- **Access**: Whitelisted buyers only (MerkleProof)  
- **Payment**: Optional ETH deposit
- **Effect**: Mints ERC-721 NFT, deposits funds to escrow, starts auction
- **Events**: `TenderCreated(tenderId, ipfsHash, buyer)`

#### `setBuyerMerkleRoot(bytes32 root)` [Owner Only]
- Updates buyer whitelist

---

### AuctionManager

#### `submitBid(uint256 tenderId, uint256 amount, string certsUri, bytes32[] proof)`
- **Access**: Whitelisted suppliers only (MerkleProof)
- **Constraints**: Before deadline, auction not closed
- **Effect**: Records bid, updates best bid if lowest
- **Events**: `BidSubmitted(tenderId, supplier, amount)`

#### `checkUpkeep(bytes)` → `(bool, bytes)`
- **Access**: Public (Chainlink Automation)
- **Returns**: Tenders past deadline ready to close

#### `performUpkeep(bytes performData)`
- **Access**: Public (Chainlink Automation)
- **Effect**: Closes auctions, selects winners
- **Events**: `AuctionClosed(tenderId, winner, amount)`

#### `setSupplierMerkleRoot(bytes32 root)` [Owner Only]
- Updates supplier whitelist

---

### EscrowVault

#### `deposit(uint256 tenderId)`
- **Access**: TenderFactory only
- **Payment**: Requires ETH
- **Effect**: Records deposit for tender
- **Events**: `DepositReceived(tenderId, amount)`

####  `releaseFunds(uint256 tenderId, address recipient, bytes32[] proof)`
- **Access**: Whitelisted admins only (MerkleProof)
- **Constraints**: Not already released
- **Effect**: 
  - Deducts 0.2% fee (20 basis points)
  - Transfers remaining funds to recipient
- **Events**: `FundsReleased(tenderId, recipient, amount, fee)`

#### `withdrawFees()`
- **Access**: Fee collector or owner
- **Effect**: Withdraws accumulated fees
- **Events**: `FeesWithdrawn(collector, amount)`

#### `setAdminMerkleRoot(bytes32 root)` [Owner Only]
- Updates admin whitelist

---

## Workflow Example

### 1. Setup (Owner)
```solidity
// Set whitelists
tenderFactory.setBuyerMerkleRoot(buyerRoot);
auctionManager.setSupplierMerkleRoot(supplierRoot);
escrowVault.setAdminMerkleRoot(adminRoot);
```

### 2. Create Tender (Buyer)
```solidity
uint256 deadline = block.timestamp + 7 days;
bytes32[] memory proof = merkleTree.getProof(msg.sender);

tenderFactory.createTender{value: 1 ether}(
    "QmIPFShash...",  // IPFS metadata
    deadline,
    proof
);
// → Tender NFT minted
// → 1 ETH locked in escrow
// → Auction started
```

### 3. Submit Bids (Suppliers)
```solidity
bytes32[] memory proof = merkleTree.getProof(msg.sender);

auctionManager.submitBid(
    0,                    // tenderId
    0.8 ether,           // bid amount
    "QmCertsHash...",    // certifications
    proof
);
```

### 4. Auto-Award (Chainlink Automation)
```solidity
// After deadline passes, Chainlink calls:
auctionManager.performUpkeep(encodedTenderIds);
// → Winner selected (lowest bid)
```

### 5. Release Funds (Admin)
```solidity
bytes32[] memory proof = merkleTree.getProof(msg.sender);

escrowVault.releaseFunds(
    0,                      // tenderId
    winnerSupplierAddress,
    proof
);
// → 0.998 ETH sent to supplier
// → 0.002 ETH collected as fee
```

---

## Security Considerations

### Access Control
- **Buyers**: Must provide MerkleProof for createTender
- **Suppliers**: Must provide MerkleProof for submitBid
- **Admins**: Must provide MerkleProof for releaseFunds
- **Owner**: Can update Merkle roots and contract addresses

### Reentrancy Protection
- ✅ `releaseFunds()` uses `ReentrancyGuard`
- ✅ `withdrawFees()` uses `ReentrancyGuard`
- ✅ State changes before external calls

### Edge Cases Handled
- ✅ Duplicate bid from same supplier (allowed, updates best)
- ✅ No bids submitted (winner = address(0))
- ✅ Auction already closed (reverts)
- ✅ Funds already released (reverts)
- ✅ Self-pairing in MerkleTree (for odd-length lists)

---

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `FEE_BASIS_POINTS` | 20 | 0.2% platform fee |
| `BASIS_POINTS` | 10000 | Fee denominator |

---

## Events Reference

### TenderFactory
- `TenderCreated(uint256 indexed tenderId, string ipfsHash, address indexed buyer)`

### AuctionManager
- `BidSubmitted(uint256 indexed tenderId, address indexed supplier, uint256 amount)`
- `AuctionStarted(uint256 indexed tenderId, uint256 deadline)`
- `AuctionClosed(uint256 indexed tenderId, address winner, uint256 amount)`

### EscrowVault
- `DepositReceived(uint256 indexed tenderId, uint256 amount)`
- `FundsReleased(uint256 indexed tenderId, address indexed recipient, uint256 amount, uint256 fee)`
- `FeesWithdrawn(address indexed collector, uint256 amount)`
- `AdminMerkleRootUpdated(bytes32 newRoot)`
- `FeeCollectorUpdated(address newCollector)`

---

## Custom Errors (EscrowVault)

- `NotAuthorized()`: Caller not in whitelist
- `NotFactory()`: Caller is not TenderFactory
- `InvalidAmount()`: Zero amount or no funds
- `AlreadyReleased()`: Funds already released for tender
- `NoFundsToWithdraw()`: No fees to collect
- `TransferFailed()`: ETH transfer failed

---

## Gas Optimization Tips

1. Use `external` over `public` when possible
2. Cache array lengths in loops
3. Use custom errors instead of require strings
4. Pack storage variables when possible
5. Use `unchecked` for safe arithmetic
6. Prefer `calldata` over `memory` for read-only arrays

---

## Testing Checklist

- [ ] Buyer can create tender with deposit
- [ ] Supplier can submit bid
- [ ] Cannot submit bid after deadline
- [ ] Chainlink automation closes auction
- [ ] Admin can release funds
- [ ] Fees are correctly calculated (0.2%)
- [ ] Cannot release twice
- [ ] Fee collector can withdraw
- [ ] MerkleProof validation works
- [ ] Reentrancy protection works
