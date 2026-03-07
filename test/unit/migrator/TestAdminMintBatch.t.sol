// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MigratorBaseTest} from "./Base.t.sol";
import {MultipliMigrator} from "src/migrator/MultipliMigrator.sol";

contract TestAdminMintBatch is MigratorBaseTest {
    uint256 INITIAL_DEPOSIT_AMOUNT;
    uint256 constant BATCH_SIZE = 3;

    function setUp() public override {
        MigratorBaseTest.setUp();
        INITIAL_DEPOSIT_AMOUNT = getQuantizedValue(1000);

        // admin performs initial deposit
        vm.startPrank(users.admin);
        approveProtocol(users.admin);
        vault.deposit(INITIAL_DEPOSIT_AMOUNT, users.admin);
        vm.stopPrank();

        addToAllowList(operator);
    }

    function test__adminMintBatch__Reverts__UnAuthorized() public {
        uint256[] memory ids = new uint256[](1);
        address[] memory receivers = new address[](1);
        uint256[] memory assets = new uint256[](1);
        uint256[] memory minShares = new uint256[](1);

        ids[0] = 1;
        receivers[0] = users.alice;
        assets[0] = getQuantizedValue(100);
        minShares[0] = getQuantizedValue(90);

        vm.startPrank(users.alice);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__UnAuthorized.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__InvalidBatchSize_EmptyArrays() public {
        uint256[] memory ids = new uint256[](0);
        address[] memory receivers = new address[](0);
        uint256[] memory assets = new uint256[](0);
        uint256[] memory minShares = new uint256[](0);

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__InvalidBatchSize.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__InvalidBatchSize_ExceedsMaximum() public {
        uint256 oversizedBatch = migrator.MAX_BATCH_SIZE() + 1;
        
        uint256[] memory ids = new uint256[](oversizedBatch);
        address[] memory receivers = new address[](oversizedBatch);
        uint256[] memory assets = new uint256[](oversizedBatch);
        uint256[] memory minShares = new uint256[](oversizedBatch);

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__InvalidBatchSize.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__ArrayLengthsMismatch_Receivers() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory receivers = new address[](3); // Different length
        uint256[] memory assets = new uint256[](2);
        uint256[] memory minShares = new uint256[](2);

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__ArrayLengthsMismatch.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__ArrayLengthsMismatch_Assets() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory receivers = new address[](2);
        uint256[] memory assets = new uint256[](1); // Different length
        uint256[] memory minShares = new uint256[](2);

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__ArrayLengthsMismatch.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__ArrayLengthsMismatch_MinShares() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory receivers = new address[](2);
        uint256[] memory assets = new uint256[](2);
        uint256[] memory minShares = new uint256[](3); // Different length

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__ArrayLengthsMismatch.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__IDAlreadyExists() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory receivers = new address[](2);
        uint256[] memory assets = new uint256[](2);
        uint256[] memory minShares = new uint256[](2);

        ids[0] = 1;
        ids[1] = 1; // Duplicate ID
        receivers[0] = users.alice;
        receivers[1] = users.bob;
        assets[0] = getQuantizedValue(100);
        assets[1] = getQuantizedValue(100);
        minShares[0] = getQuantizedValue(90);
        minShares[1] = getQuantizedValue(90);

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__IDAlreadyExists.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Reverts__InsufficientSharesReceived() public {
        uint256[] memory ids = new uint256[](1);
        address[] memory receivers = new address[](1);
        uint256[] memory assets = new uint256[](1);
        uint256[] memory minShares = new uint256[](1);

        ids[0] = 1;
        receivers[0] = users.alice;
        assets[0] = getQuantizedValue(100);
        minShares[0] = getQuantizedValue(1000); // Unrealistically high min shares

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(
            MultipliMigrator.MultipliMigrator__InsufficientSharesReceived.selector,
            getQuantizedValue(100), // Expected shares (1:1 ratio)
            getQuantizedValue(1000) // Min shares required
        ));
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

    function test__adminMintBatch__Success__SingleMigration() public {
        uint256[] memory ids = new uint256[](1);
        address[] memory receivers = new address[](1);
        uint256[] memory assets = new uint256[](1);
        uint256[] memory minShares = new uint256[](1);

        ids[0] = 1;
        receivers[0] = users.alice;
        assets[0] = getQuantizedValue(100);
        minShares[0] = getQuantizedValue(90);

        uint256 expectedShares = vault.previewDeposit(assets[0]);
        uint256 expectedNewBalance = assets[0];

        vm.startPrank(operator);
        
        // Expect individual migration event
        vm.expectEmit(true, true, true, true);
        emit MultipliMigrator.UserMigrated(ids[0], receivers[0], assets[0], expectedShares);
        
        // Expect batch completion event
        vm.expectEmit(true, true, true, true);
        emit MultipliMigrator.UserMigrated(expectedNewBalance);
        
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();

        assertEq(vault.balanceOf(users.alice), expectedShares, "alice shares mismatch");
        assertTrue(migrator.migrationID(ids[0]), "migration ID should be marked as used");
        assertEq(vault.aggregatedUnderlyingBalances(), expectedNewBalance, "underlying balance mismatch");
    }

    function test__adminMintBatch__Success__MultipleMigrations() public {
        uint256[] memory ids = new uint256[](BATCH_SIZE);
        address[] memory receivers = new address[](BATCH_SIZE);
        uint256[] memory assets = new uint256[](BATCH_SIZE);
        uint256[] memory minShares = new uint256[](BATCH_SIZE);

        // Setup batch data
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        receivers[0] = users.alice;
        receivers[1] = users.bob;
        receivers[2] = operator;
        assets[0] = getQuantizedValue(100);
        assets[1] = getQuantizedValue(200);
        assets[2] = getQuantizedValue(150);
        minShares[0] = getQuantizedValue(90);
        minShares[1] = getQuantizedValue(180);
        minShares[2] = getQuantizedValue(140);

        uint256 totalAssets = assets[0] + assets[1] + assets[2];
        uint256 expectedNewBalance = totalAssets;

        uint256[] memory expectedShares = new uint256[](BATCH_SIZE);
        for (uint256 i = 0; i < BATCH_SIZE; i++) {
            expectedShares[i] = vault.previewDeposit(assets[i]);
        }

        vm.startPrank(operator);
        
        // Expect individual migration events
        for (uint256 i = 0; i < BATCH_SIZE; i++) {
            vm.expectEmit(true, true, true, true);
            emit MultipliMigrator.UserMigrated(ids[i], receivers[i], assets[i], expectedShares[i]);
        }
        
        // Expect batch completion event
        vm.expectEmit(true, true, true, true);
        emit MultipliMigrator.UserMigrated(expectedNewBalance); // emit UserMigrated(newAggregatedBalance: 450000000 [4.5e8])
        
        migrator.adminMintBatch(ids, receivers, assets, minShares); // emit UserMigrated(newAggregatedBalance: 450000000 [4.5e8])
        vm.stopPrank();

        // Verify individual migrations
        for (uint256 i = 0; i < BATCH_SIZE; i++) {
            assertEq(vault.balanceOf(receivers[i]), expectedShares[i], "receiver shares mismatch");
            assertTrue(migrator.migrationID(ids[i]), "migration ID should be marked as used");
        }

        // Verify total state
        uint256 totalExpectedShares = expectedShares[0] + expectedShares[1] + expectedShares[2];
        assertEq(vault.totalSupply(), totalExpectedShares + INITIAL_DEPOSIT_AMOUNT, "total supply mismatch");
        assertEq(vault.aggregatedUnderlyingBalances(), expectedNewBalance, "underlying balance mismatch");
    }

    function test__adminMintBatch__Success__MaxBatchSize() public {
        uint256 maxBatch = migrator.MAX_BATCH_SIZE();
        
        uint256[] memory ids = new uint256[](maxBatch);
        address[] memory receivers = new address[](maxBatch);
        uint256[] memory assets = new uint256[](maxBatch);
        uint256[] memory minShares = new uint256[](maxBatch);

        uint256 totalAssets = 0;
        
        for (uint256 i = 0; i < maxBatch; i++) {
            ids[i] = i + 1;
            receivers[i] = users.alice;
            assets[i] = getQuantizedValue(10); // Small amount to avoid gas issues
            minShares[i] = getQuantizedValue(9);
            totalAssets += assets[i];
        }

        uint256 expectedNewBalance = totalAssets;

        vm.startPrank(operator);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();

        // Verify all migrations were processed
        for (uint256 i = 0; i < maxBatch; i++) {
            assertTrue(migrator.migrationID(ids[i]), "migration ID should be marked as used");
        }

        assertEq(vault.aggregatedUnderlyingBalances(), expectedNewBalance, "underlying balance mismatch");
    }

    function test__adminMintBatch__Success__DifferentReceivers() public {
        uint256[] memory ids = new uint256[](3);
        address[] memory receivers = new address[](3);
        uint256[] memory assets = new uint256[](3);
        uint256[] memory minShares = new uint256[](3);

        assertEq(vault.balanceOf(users.alice), 0, "balance should be 0");

        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        receivers[0] = users.alice;
        receivers[1] = users.bob;
        receivers[2] = users.alice; // Alice gets two migrations
        assets[0] = getQuantizedValue(100);
        assets[1] = getQuantizedValue(100);
        assets[2] = getQuantizedValue(100);
        minShares[0] = getQuantizedValue(100);
        minShares[1] = getQuantizedValue(100);
        minShares[2] = getQuantizedValue(100);


        uint256 expectedSharesPerMigration = vault.previewDeposit(getQuantizedValue(100));

        vm.startPrank(operator);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();

        // Alice should have shares from two migrations
        assertEq(vault.balanceOf(users.alice), expectedSharesPerMigration + expectedSharesPerMigration, "alice shares mismatch");
        // Bob should have shares from one migration
        assertEq(vault.balanceOf(users.bob), expectedSharesPerMigration, "bob shares mismatch");
    }

    function testFuzz__adminMintBatch__Success(
        uint8 batchSize,
        uint256 assetAmount
    ) public {
        // Bound inputs
        batchSize = uint8(bound(batchSize, 1, migrator.MAX_BATCH_SIZE()));
        assetAmount = bound(assetAmount, 1, getQuantizedValue(100)); // Keep amounts reasonable for gas

        uint256 aliceBalance = vault.balanceOf(users.alice);

        uint256[] memory ids = new uint256[](batchSize);
        address[] memory receivers = new address[](batchSize);
        uint256[] memory assets = new uint256[](batchSize);
        uint256[] memory minShares = new uint256[](batchSize);

        uint256 totalAssets = 0;
        
        for (uint256 i = 0; i < batchSize; i++) {
            ids[i] = i + 1;
            receivers[i] = users.alice;
            assets[i] = assetAmount;
            minShares[i] = 0; // No minimum requirement for fuzz test
            totalAssets += assetAmount;
        }

        uint256 expectedNewBalance = totalAssets;

        vm.startPrank(operator);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();

        // Verify final state
        assertEq(vault.aggregatedUnderlyingBalances(), expectedNewBalance, "underlying balance mismatch");
        assertEq(vault.balanceOf(users.alice), aliceBalance + totalAssets, "alice should have received shares");
        
        // Verify all migration IDs were marked as used
        for (uint256 i = 0; i < batchSize; i++) {
            assertTrue(migrator.migrationID(ids[i]), "migration ID should be marked as used");
        }
    }

    function testFuzz__adminMintBatch__InvalidAddress(
        uint8 batchSize,
        uint256 assetAmount
    ) public {
        // Bound inputs
        batchSize = uint8(bound(batchSize, 1, migrator.MAX_BATCH_SIZE()));
        assetAmount = bound(assetAmount, 1, getQuantizedValue(100)); // Keep amounts reasonable for gas

        uint256 aliceBalance = vault.balanceOf(users.alice);

        uint256[] memory ids = new uint256[](batchSize);
        address[] memory receivers = new address[](batchSize);
        uint256[] memory assets = new uint256[](batchSize);
        uint256[] memory minShares = new uint256[](batchSize);

        
        for (uint256 i = 0; i < batchSize; i++) {
            ids[i] = i + 1;
            receivers[i] = users.alice;
            assets[i] = assetAmount;
            minShares[i] = 0; // No minimum requirement for fuzz test
        }
        
       
        receivers[0] = address(0); // Invalid address


        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__InvalidAddress.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();

         // Verify final state
        assertEq(vault.aggregatedUnderlyingBalances(), 0, "underlying balance should not increase");
        assertEq(vault.balanceOf(users.alice), aliceBalance, "alice should not receieve shares");


        for (uint256 i = 0; i < batchSize; i++) {
            assertFalse(migrator.migrationID(ids[i]), "migration ID should not be marked as used");
        }

    }

    function test__adminMintBatch__Reverts__ZeroAmount() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory receivers = new address[](2);
        uint256[] memory assets = new uint256[](2);
        uint256[] memory minShares = new uint256[](2);

        ids[0] = 1;
        ids[1] = 2;
        receivers[0] = users.alice;
        receivers[1] = users.bob;
        assets[0] = getQuantizedValue(100);
        assets[1] = 0; // Zero amount
        minShares[0] = getQuantizedValue(90);
        minShares[1] = 0;

        vm.startPrank(operator);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__ZeroAmount.selector);
        migrator.adminMintBatch(ids, receivers, assets, minShares);
        vm.stopPrank();
    }

}