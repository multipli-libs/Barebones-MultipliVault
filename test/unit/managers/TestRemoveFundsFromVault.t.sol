// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";

contract TestRemoveFundsFromVault is VaultFundManagerBase {
    event FundsRemovedFromVault(address indexed recipient, uint256 amount, uint256 newAggregatedBalance);

    function setUp() public override {
        super.setUp();

        // Deposit funds into vault for testing
        depositForUser(users.alice, INITIAL_DEPOSIT);
    }

    function test_RemoveFundsFromVault_RevertsWhenNotCalledByVault() public {
        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.removeFundsFromVault(recipient1, TEST_TRANSFER_AMOUNT);
    }

    function test_RemoveFundsFromVault_RevertsWithZeroRecipient() public {
        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, address(0), TEST_TRANSFER_AMOUNT);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsFromVault_RevertsWithZeroAmount() public {
        bytes memory data = abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, 0);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.ZeroAmount.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsFromVault_RevertsWithInsufficientBalance() public {
        uint256 vaultBalance = token.balanceOf(address(vault));
        uint256 excessiveAmount = vaultBalance + 1;

        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, excessiveAmount);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.InsufficientBalance.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsFromVault_RevertsWithNonWhitelistedRecipient() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, nonWhitelistedRecipient, TEST_TRANSFER_AMOUNT
        );

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("RecipientNotWhitelisted()")); // Should revert due to non-whitelisted recipient
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsFromVault_Success() public {
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialRecipientBalance = token.balanceOf(recipient1);
        uint256 initialAggregatedBalance = vault.aggregatedUnderlyingBalances();
        uint256 initialTotalAssets = vault.totalAssets();

        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, TEST_TRANSFER_AMOUNT);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Check balances
        assertEq(token.balanceOf(address(vault)), initialVaultBalance - TEST_TRANSFER_AMOUNT);
        assertEq(token.balanceOf(recipient1), initialRecipientBalance + TEST_TRANSFER_AMOUNT);

        // Check aggregated balance increased
        assertEq(vault.aggregatedUnderlyingBalances(), initialAggregatedBalance + TEST_TRANSFER_AMOUNT);

        // Check total assets remain the same
        assertEq(vault.totalAssets(), initialTotalAssets);
    }

    function test_RemoveFundsFromVault_EmitsCorrectEvent() public {
        uint256 expectedNewAggregatedBalance = vault.aggregatedUnderlyingBalances() + TEST_TRANSFER_AMOUNT;

        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, TEST_TRANSFER_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit FundsRemovedFromVault(recipient1, TEST_TRANSFER_AMOUNT, expectedNewAggregatedBalance);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsFromVault_MaintainsTotalAssetsInvariant() public {
        uint256 totalAssetsBefore = vault.totalAssets();

        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, TEST_TRANSFER_AMOUNT);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        uint256 totalAssetsAfter = vault.totalAssets();
        assertEq(totalAssetsBefore, totalAssetsAfter, "Total assets should remain constant");
    }

    function test_RemoveFundsFromVault_MaintainsTotalSupplyInvariant() public {
        uint256 totalSupplyBefore = vault.totalSupply();

        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, TEST_TRANSFER_AMOUNT);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        uint256 totalAssetsAfter = vault.totalSupply();
        assertEq(totalSupplyBefore, totalAssetsAfter, "Total supply should remain constant");
    }

    function test_RemoveFundsFromVault_WithMaximumAmount() public {
        uint256 vaultBalance = token.balanceOf(address(vault));
        assertEq(vaultBalance, INITIAL_DEPOSIT, "vault balance mismatch");
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        bytes memory data = abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, vaultBalance);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Vault should have zero balance
        assertEq(token.balanceOf(address(vault)), 0);

        // Recipient should receive full amount
        assertEq(token.balanceOf(recipient1), vaultBalance);

        // Total assets should remain the same
        assertEq(vault.totalAssets(), totalAssetsBefore);

        // total supply should remain the same
        assertEq(vault.totalSupply(), totalAssetsBefore);

        // Aggregated balance should increase by the full amount
        assertEq(vault.aggregatedUnderlyingBalances(), vaultBalance);
    }

    function test_RemoveFundsFromVault_MultipleTransfers() public {
        uint256 firstTransfer = getQuantizedValue(20_000);
        uint256 secondTransfer = getQuantizedValue(15_000);
        uint256 initialTotalAssets = vault.totalAssets();

        // First transfer
        bytes memory data1 =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, firstTransfer);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data1, 0);

        vm.roll(block.number + 1);

        // Second transfer
        bytes memory data2 =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient2, secondTransfer);

        vault.manage(address(fundManager), data2, 0);

        // Check final state
        assertEq(token.balanceOf(recipient1), firstTransfer);
        assertEq(token.balanceOf(recipient2), secondTransfer);
        assertEq(vault.aggregatedUnderlyingBalances(), firstTransfer + secondTransfer);
        assertEq(vault.totalAssets(), initialTotalAssets);
    }

    function test_RemoveFundsFromVault_MultipleTransfersInSameBlock() public {
        uint256 firstTransfer = getQuantizedValue(20_000);
        uint256 secondTransfer = getQuantizedValue(15_000);
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 oldAggregatedUnderlyingBalance = vault.aggregatedUnderlyingBalances();

        // First transfer
        bytes memory data1 =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, firstTransfer);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data1, 0);

        // Second transfer
        bytes memory data2 =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient2, secondTransfer);

        vm.expectRevert(abi.encodeWithSignature("UpdateAlreadyCompletedInThisBlock()"));
        vault.manage(address(fundManager), data2, 0);

        // only first manage call works
        assertEq(token.balanceOf(recipient1), firstTransfer);
        assertEq(token.balanceOf(recipient2), 0);
        assertEq(vault.aggregatedUnderlyingBalances(), oldAggregatedUnderlyingBalance + firstTransfer);
        assertEq(vault.totalAssets(), initialTotalAssets);
    }
}
