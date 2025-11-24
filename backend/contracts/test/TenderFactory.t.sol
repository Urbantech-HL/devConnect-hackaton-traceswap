// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../TenderFactory.sol";
import "../EscrowVault.sol";
import "../AuctionManager.sol";

/**
 * @title TenderFactoryTest
 * @notice Tests for TenderFactory with AccessControl and immutable references
 * @dev Uses a simplified setup that avoids circular dependency issues
 */
contract TenderFactoryTest is Test {
    TenderFactory factory;

    address owner = address(0x1);
    address buyer = address(0x2);
    address feeCollector = address(0x3);
    address mockEscrow = address(0x4);
    address mockAuction = address(0x5);

    bytes32 buyerRoot;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy TenderFactory with mock addresses for unit testing
        factory = new TenderFactory(mockEscrow, mockAuction);

        // Setup Merkle Root for buyer (Single leaf tree)
        bytes32 leaf = keccak256(abi.encodePacked(buyer));
        buyerRoot = leaf;
        factory.setBuyerMerkleRoot(buyerRoot);

        vm.stopPrank();
    }

    function test_CreateTenderWithoutValue() public {
        vm.startPrank(buyer);

        // Mock the auction manager call
        vm.mockCall(
            mockAuction,
            abi.encodeWithSignature(
                "startAuction(uint256,uint256)",
                0,
                block.timestamp + 1 days
            ),
            abi.encode()
        );

        // Create tender without value (no escrow deposit)
        factory.createTender(
            "QmHash",
            block.timestamp + 1 days,
            new bytes32[](0)
        );

        assertEq(factory.ownerOf(0), buyer);
        vm.stopPrank();
    }

    function test_CreateTenderWithValue() public {
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);

        // Mock the escrow deposit call
        vm.mockCall(
            mockEscrow,
            abi.encodeWithSignature("deposit(uint256)", 0),
            abi.encode()
        );

        // Mock the auction manager call
        vm.mockCall(
            mockAuction,
            abi.encodeWithSignature(
                "startAuction(uint256,uint256)",
                0,
                block.timestamp + 1 days
            ),
            abi.encode()
        );

        // Create tender with value
        factory.createTender{value: 1 ether}(
            "QmHash",
            block.timestamp + 1 days,
            new bytes32[](0)
        );

        assertEq(factory.ownerOf(0), buyer);
        vm.stopPrank();
    }

    function test_RevertIfUnauthorized() public {
        address other = address(0x99);
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                TenderFactory.UnauthorizedBuyer.selector,
                other
            )
        );
        factory.createTender(
            "QmHash",
            block.timestamp + 1 days,
            new bytes32[](0)
        );
    }

    function test_SupportsInterface() public view {
        // Test ERC721 interface
        bytes4 erc721Interface = 0x80ac58cd;
        assertTrue(factory.supportsInterface(erc721Interface));

        // Test AccessControl interface
        bytes4 accessControlInterface = 0x7965db0b;
        assertTrue(factory.supportsInterface(accessControlInterface));
    }

    function test_AdminRole() public {
        vm.startPrank(owner);

        bytes32 newRoot = keccak256("new root");
        factory.setBuyerMerkleRoot(newRoot);

        assertEq(factory.buyerMerkleRoot(), newRoot);
        vm.stopPrank();
    }

    function test_RevertIfNonAdminSetsMerkleRoot() public {
        vm.prank(buyer);
        bytes32 newRoot = keccak256("new root");

        vm.expectRevert();
        factory.setBuyerMerkleRoot(newRoot);
    }

    function test_ImmutableAddresses() public view {
        // Verify immutable addresses are set correctly
        assertEq(factory.escrowVault(), mockEscrow);
        assertEq(factory.auctionManager(), mockAuction);
    }

    function test_HasAdminRole() public view {
        bytes32 adminRole = factory.ADMIN_ROLE();
        assertTrue(factory.hasRole(adminRole, owner));
    }

    function test_HasDefaultAdminRole() public view {
        bytes32 defaultAdminRole = factory.DEFAULT_ADMIN_ROLE();
        assertTrue(factory.hasRole(defaultAdminRole, owner));
    }

    function test_RevertOnInvalidConstructorAddress() public {
        vm.expectRevert(TenderFactory.InvalidAddress.selector);
        new TenderFactory(address(0), mockAuction);

        vm.expectRevert(TenderFactory.InvalidAddress.selector);
        new TenderFactory(mockEscrow, address(0));
    }
}
