// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../AuctionManager.sol";

contract AuctionManagerTest is Test {
    AuctionManager manager;
    address owner = address(0x1);
    address factory = address(0x2);
    address supplier1 = address(0x3);
    address supplier2 = address(0x4);

    bytes32 supplierRoot;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy with factory address in constructor
        manager = new AuctionManager(factory);

        // Setup Merkle Root for supplier1 (Single leaf)
        bytes32 leaf = keccak256(abi.encodePacked(supplier1));
        supplierRoot = leaf;
        manager.setSupplierMerkleRoot(supplierRoot);

        vm.stopPrank();
    }

    function test_StartAuction() public {
        vm.prank(factory);
        manager.startAuction(0, block.timestamp + 1 days);

        (uint256 deadline, bool closed, , , , ) = manager.auctions(0);
        assertEq(deadline, block.timestamp + 1 days);
        assertEq(closed, false);
    }

    function test_SubmitBid() public {
        // Start auction first
        vm.prank(factory);
        manager.startAuction(0, block.timestamp + 1 days);

        vm.prank(supplier1);
        manager.submitBid(0, 100, "QmCerts", new bytes32[](0));

        (, , , , address bestBidder, uint256 bestBidAmount) = manager.auctions(
            0
        );
        assertEq(bestBidder, supplier1);
        assertEq(bestBidAmount, 100);
    }

    function test_RevertIfUnauthorizedSupplier() public {
        vm.prank(factory);
        manager.startAuction(0, block.timestamp + 1 days);

        vm.prank(supplier2);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuctionManager.UnauthorizedSupplier.selector,
                supplier2
            )
        );
        manager.submitBid(0, 100, "QmCerts", new bytes32[](0));
    }

    function test_CheckUpkeep() public {
        vm.prank(factory);
        manager.startAuction(0, block.timestamp + 1 hours);

        // Time travel
        vm.warp(block.timestamp + 1 hours + 1);

        (bool upkeepNeeded, bytes memory performData) = manager.checkUpkeep("");
        assertTrue(upkeepNeeded);

        uint256[] memory tenders = abi.decode(performData, (uint256[]));
        assertEq(tenders.length, 1);
        assertEq(tenders[0], 0);
    }

    function test_PerformUpkeep() public {
        vm.prank(factory);
        manager.startAuction(0, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256[] memory tenders = new uint256[](1);
        tenders[0] = 0;

        manager.performUpkeep(abi.encode(tenders));

        (, bool closed, address winner, , , ) = manager.auctions(0);
        assertTrue(closed);
    }

    function test_AdminRole() public {
        vm.startPrank(owner);

        bytes32 newRoot = keccak256("new root");
        manager.setSupplierMerkleRoot(newRoot);

        assertEq(manager.supplierMerkleRoot(), newRoot);
        vm.stopPrank();
    }

    function test_RevertIfNonAdminSetsMerkleRoot() public {
        vm.prank(supplier1);
        bytes32 newRoot = keccak256("new root");

        vm.expectRevert();
        manager.setSupplierMerkleRoot(newRoot);
    }

    function test_RevertIfNonFactoryStartsAuction() public {
        vm.prank(owner);

        vm.expectRevert();
        manager.startAuction(0, block.timestamp + 1 days);
    }

    function test_ImmutableFactory() public view {
        // Verify factory address is set correctly and immutable
        assertEq(manager.tenderFactory(), factory);
    }
}
