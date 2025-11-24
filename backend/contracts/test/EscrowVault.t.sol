// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../EscrowVault.sol";

contract EscrowVaultTest is Test {
    EscrowVault vault;
    address owner = address(0x1);
    address factory = address(0x2);
    address admin = address(0x3);
    address supplier = address(0x4);
    address feeCollector = address(0x5);

    bytes32 adminRoot;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy with factory and feeCollector in constructor
        vault = new EscrowVault(factory, feeCollector);

        // Setup Merkle Root for admin
        bytes32 leaf = keccak256(abi.encodePacked(admin));
        adminRoot = leaf;
        vault.setAdminMerkleRoot(adminRoot);

        vm.stopPrank();
    }

    function test_Deposit() public {
        vm.deal(factory, 10 ether);
        vm.prank(factory);
        vault.deposit{value: 1 ether}(0);

        assertEq(vault.getDeposit(0), 1 ether);
    }

    function test_ReleaseFunds() public {
        // Deposit first
        vm.deal(factory, 10 ether);
        vm.prank(factory);
        vault.deposit{value: 1 ether}(0);

        uint256 initialBalance = supplier.balance;

        vm.prank(admin);
        vault.releaseFunds(0, supplier, new bytes32[](0));

        assertTrue(vault.isReleased(0));

        // Check fee (0.2% = 0.002 ether)
        uint256 fee = 0.002 ether;
        uint256 payment = 1 ether - fee;

        assertEq(supplier.balance - initialBalance, payment);
        assertEq(vault.totalFeesCollected(), fee);
    }

    function test_RevertIfAlreadyReleased() public {
        vm.deal(factory, 10 ether);
        vm.prank(factory);
        vault.deposit{value: 1 ether}(0);

        vm.prank(admin);
        vault.releaseFunds(0, supplier, new bytes32[](0));

        vm.prank(admin);
        vm.expectRevert(EscrowVault.AlreadyReleased.selector);
        vault.releaseFunds(0, supplier, new bytes32[](0));
    }

    function test_WithdrawFees() public {
        // Simulate fee collection
        vm.deal(factory, 10 ether);
        vm.prank(factory);
        vault.deposit{value: 1 ether}(0);

        vm.prank(admin);
        vault.releaseFunds(0, supplier, new bytes32[](0));

        uint256 fees = vault.totalFeesCollected();
        uint256 collectorBalance = feeCollector.balance;

        vm.prank(feeCollector);
        vault.withdrawFees();

        assertEq(feeCollector.balance - collectorBalance, fees);
        assertEq(vault.totalFeesCollected(), 0);
    }

    function test_AdminRole() public {
        vm.startPrank(owner);

        bytes32 newRoot = keccak256("new root");
        vault.setAdminMerkleRoot(newRoot);

        assertEq(vault.adminMerkleRoot(), newRoot);
        vm.stopPrank();
    }

    function test_RevertIfNonAdminSetsMerkleRoot() public {
        vm.prank(admin);
        bytes32 newRoot = keccak256("new root");

        vm.expectRevert();
        vault.setAdminMerkleRoot(newRoot);
    }

    function test_RevertIfNonFactoryDeposits() public {
        vm.deal(owner, 10 ether);
        vm.prank(owner);

        vm.expectRevert();
        vault.deposit{value: 1 ether}(0);
    }

    function test_ImmutableAddresses() public view {
        // Verify immutable addresses are set correctly
        assertEq(vault.tenderFactory(), factory);
        assertEq(vault.feeCollector(), feeCollector);
    }

    function test_RevertIfUnauthorizedRelease() public {
        vm.deal(factory, 10 ether);
        vm.prank(factory);
        vault.deposit{value: 1 ether}(0);

        address unauthorized = address(0x99);
        vm.prank(unauthorized);
        vm.expectRevert(EscrowVault.NotAuthorized.selector);
        vault.releaseFunds(0, supplier, new bytes32[](0));
    }
}
