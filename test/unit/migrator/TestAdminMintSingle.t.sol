// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MigratorBaseTest} from "./Base.t.sol";
import {MultipliMigrator} from "src/migrator/MultipliMigrator.sol";

import {IMultipliVault} from "src/interfaces/IMultipliVault.sol";


contract TestAdminMintSingle is MigratorBaseTest {
    uint256 constant MIGRATION_ID = 12345;
    uint256 public INITIAL_VAULT_DEPOSIT;
    uint256 public ASSETS_AMOUNT;
    uint256 public MIN_SHARES;

    function setUp() public override {
        MigratorBaseTest.setUp();
        INITIAL_VAULT_DEPOSIT = getQuantizedValue(100);
        ASSETS_AMOUNT = getQuantizedValue(100);
        MIN_SHARES = getQuantizedValue(90);

        // admin performs initial deposit
        vm.startPrank(users.admin);
        approveProtocol(users.admin);
        vault.deposit(INITIAL_VAULT_DEPOSIT, users.admin);
        vm.stopPrank();

        addToAllowList(operator);

    }

    function test__adminMintSingle__Reverts__UnAuthorized() public {
        vm.startPrank(users.alice);
        vm.expectRevert(MultipliMigrator.UnAuthorized.selector);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();
    }

    function test__adminMintSingle__Reverts__InvalidReceiverAddress() public {
        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.InvalidAddress.selector);
        migrator.adminMintSingle(MIGRATION_ID, address(0), ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();
    }

    function test__adminMintSingle__Reverts__ZeroAmount() public {
        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.ZeroAmount.selector);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, 0, MIN_SHARES);
        vm.stopPrank();
    }

    function test__adminMintSingle__Reverts__IDAlreadyExists() public {
        // First migration
        vm.startPrank(operator);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();

        // Try to use same ID again
        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.IDAlreadyExists.selector);
        migrator.adminMintSingle(MIGRATION_ID, users.bob, ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();
    }

    function test__adminMintSingle__Reverts__InsufficientSharesReceived() public {
        uint256 highMinShares = ASSETS_AMOUNT * 2; // Set unrealistically high min shares

        uint256 shares = vault.previewDeposit(ASSETS_AMOUNT);

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(
            MultipliMigrator.InsufficientSharesReceived.selector,
            shares, // (error will have the shares that previewRedeem spits out)
            highMinShares
        ));
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, highMinShares);
        vm.stopPrank();
    }

    function test__adminMintSingle__Reverts__VaultUpdateAlreadyCompletedInThisBlock() public {
        // First migration in the block
        vm.startPrank(operator);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, MIN_SHARES);

        // Try second migration in same block (should fail due to vault's one-per-block limit)
        vm.expectRevert("UpdateAlreadyCompletedInThisBlock()");
        migrator.adminMintSingle(MIGRATION_ID + 1, users.bob, ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();
    }

    function test__adminMintSingle__Success__BasicMigration() public {
        uint256 aliceSharesBefore = vault.balanceOf(users.alice);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 underlyingBalanceBefore = vault.aggregatedUnderlyingBalances();

        uint256 expectedShares = vault.previewDeposit(ASSETS_AMOUNT);
        uint256 expectedNewBalance = underlyingBalanceBefore + ASSETS_AMOUNT;

        vm.startPrank(operator);

       
        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.UnderlyingBalanceUpdated(0, expectedNewBalance);

        // this is failing
        vm.expectEmit(true, true, true, true);
        emit MultipliMigrator.UserMigrated(MIGRATION_ID, users.alice, ASSETS_AMOUNT, expectedShares, expectedNewBalance);

        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, MIN_SHARES);
        vm.stopPrank();

        // Verify shares were minted
        assertEq(vault.balanceOf(users.alice), aliceSharesBefore + expectedShares, "alice shares mismatch");
        assertEq(vault.totalSupply(), totalSupplyBefore + expectedShares, "total supply mismatch");

        // Verify underlying balance was updated
        assertEq(vault.aggregatedUnderlyingBalances(), expectedNewBalance, "underlying balance mismatch");

        // Verify migration ID was marked as used
        assertTrue(migrator.migrationID(MIGRATION_ID), "migration ID should be marked as used");

    }

    function test__adminMintSingle__Success__ExactMinShares() public {
        uint256 expectedShares = vault.previewDeposit(ASSETS_AMOUNT);

        vm.startPrank(operator);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, expectedShares);
        vm.stopPrank();

        assertEq(vault.balanceOf(users.alice), expectedShares, "shares mismatch");
        assertTrue(migrator.migrationID(MIGRATION_ID), "migration ID should be marked as used");
    }

    function test__adminMintSingle__Success__LowMinShares() public {
        uint256 lowMinShares = 1;

        vm.startPrank(operator);
        migrator.adminMintSingle(MIGRATION_ID, users.alice, ASSETS_AMOUNT, lowMinShares);
        vm.stopPrank();

        assertGt(vault.balanceOf(users.alice), lowMinShares, "should receive more than min shares");
        assertTrue(migrator.migrationID(MIGRATION_ID), "migration ID should be marked as used");
    }

    function test__adminMintSingle__Success__MultipleSequentialMigrations() public {
        uint256 initialTotalSupply = vault.totalSupply();

        uint256[] memory migrationIds = new uint256[](3);
        migrationIds[0] = 1;
        migrationIds[1] = 2;
        migrationIds[2] = 3;

        address[] memory recipients = new address[](3);
        recipients[0] = users.alice;
        recipients[1] = users.bob;
        recipients[2] = operator;

        uint256 totalExpectedShares = 0;
        uint256 totalExpectedAssets = 0;

        vm.startPrank(operator);
        
        for (uint256 i = 0; i < migrationIds.length; i++) {
            // Move to next block to avoid one-per-block limit
            vm.roll(block.number + 1);
            
            uint256 expectedShares = vault.previewDeposit(ASSETS_AMOUNT);
            totalExpectedShares += expectedShares;
            totalExpectedAssets += ASSETS_AMOUNT;

            migrator.adminMintSingle(migrationIds[i], recipients[i], ASSETS_AMOUNT, MIN_SHARES);

            // Verify each migration
            assertTrue(migrator.migrationID(migrationIds[i]), "migration ID should be marked as used");
            assertEq(vault.balanceOf(recipients[i]), expectedShares, "recipient shares mismatch");
        }

        vm.stopPrank();

        // Verify total state
        assertEq(vault.totalSupply(), initialTotalSupply + totalExpectedShares, "total supply mismatch");
        assertEq(vault.aggregatedUnderlyingBalances(), totalExpectedAssets, "final underlying balance mismatch");
    }

    function testFuzz__adminMintSingle__Success(
        uint256 migrationId,
        uint256 assets,
        uint256 minShares
    ) public {
        // Bound inputs to reasonable ranges
        migrationId = bound(migrationId, 1, type(uint256).max);
        assets = bound(assets, 1, getQuantizedValue(1_000_000)); // 1 to 1M tokens
        
        uint256 expectedShares = vault.previewDeposit(assets);
        minShares = bound(minShares, 0, expectedShares); // Can't require more shares than would be minted

        vm.startPrank(operator);
        migrator.adminMintSingle(migrationId, users.alice, assets, minShares);
        vm.stopPrank();

        assertEq(vault.balanceOf(users.alice), expectedShares, "shares mismatch");
        assertTrue(migrator.migrationID(migrationId), "migration ID should be marked as used");
        assertEq(vault.aggregatedUnderlyingBalances(), assets, "underlying balance mismatch");
    }
}