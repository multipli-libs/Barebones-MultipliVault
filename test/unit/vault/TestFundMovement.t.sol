// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";

import {FundMovementHelperUpgradeable} from "src/base/FundMovementHelperUpgradeable.sol";

contract TestFundMovement is BaseTest {
    // Test users for fund movement
    address internal recipient1;
    address internal recipient2;
    address internal unauthorizedUser;

    function setUp() public override {
        BaseTest.setUp();

        // Create additional test users
        recipient1 = makeAddr("Recipient1");
        recipient2 = makeAddr("Recipient2");
        unauthorizedUser = makeAddr("UnauthorizedUser");

        // Fund the vault with some USDC for testing removeFunds
        vm.startPrank(users.alice);
        usdc.approve(address(depositVault), 10_000e6);
        depositVault.deposit(10_000e6, users.alice);
        vm.stopPrank();
    }

    // ========================================= isRecipientWhitelisted TESTS =========================================

    function test_isRecipientWhitelisted_ReturnsFalseForNonWhitelistedUser() public {
        assertFalse(depositVault.isRecipientWhitelisted(recipient1), "Non-whitelisted user should return false");
    }

    function test_isRecipientWhitelisted_ReturnsTrueForWhitelistedUser() public {
        // Whitelist recipient1
        vm.startPrank(users.admin);
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        vm.stopPrank();

        assertTrue(depositVault.isRecipientWhitelisted(recipient1), "Whitelisted user should return true");
    }

    function test_isRecipientWhitelisted_ReturnsFalseAfterRemovingFromWhitelist() public {
        // First whitelist, then remove
        vm.startPrank(users.admin);
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        depositVault.whitelistFundTransferRecipient(recipient1, false);
        vm.stopPrank();

        assertFalse(depositVault.isRecipientWhitelisted(recipient1), "Removed user should return false");
    }

    function test_isRecipientWhitelisted_WithZeroAddress() public {
        assertFalse(depositVault.isRecipientWhitelisted(address(0)), "Zero address should return false");
    }

    // ========================================= whitelistFundTransferRecipient TESTS =========================================

    function test_whitelistFundTransferRecipient_Success_AddToWhitelist() public {
        vm.startPrank(users.admin);

        // Expect WhitelistUpdated event
        vm.expectEmit(true, true, true, true);
        emit FundMovementHelperUpgradeable.WhitelistUpdated(users.admin, recipient1, true);

        depositVault.whitelistFundTransferRecipient(recipient1, true);

        assertTrue(depositVault.isRecipientWhitelisted(recipient1), "User should be whitelisted");
        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_Success_RemoveFromWhitelist() public {
        vm.startPrank(users.admin);

        // First add to whitelist
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // Then remove and expect event
        vm.expectEmit(true, true, true, true);
        emit FundMovementHelperUpgradeable.WhitelistUpdated(users.admin, recipient1, false);

        depositVault.whitelistFundTransferRecipient(recipient1, false);

        assertFalse(depositVault.isRecipientWhitelisted(recipient1), "User should be removed from whitelist");
        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_Success_MultipleUsers() public {
        vm.startPrank(users.admin);

        depositVault.whitelistFundTransferRecipient(recipient1, true);
        depositVault.whitelistFundTransferRecipient(recipient2, true);

        assertTrue(depositVault.isRecipientWhitelisted(recipient1), "Recipient1 should be whitelisted");
        assertTrue(depositVault.isRecipientWhitelisted(recipient2), "Recipient2 should be whitelisted");
        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_Reverts_WithZeroAddress() public {
        vm.startPrank(users.admin);

        vm.expectRevert(FundMovementHelperUpgradeable.AddressZero.selector);
        depositVault.whitelistFundTransferRecipient(address(0), true);

        assertFalse(depositVault.isRecipientWhitelisted(address(0)), "Zero address should be whitelisted");
        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_RevertsWhen_NoChangeInStatus() public {
        vm.startPrank(users.admin);

        // First set to true
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // Try to set to true again - should revert
        vm.expectRevert(FundMovementHelperUpgradeable.NoChangeInWhitelistStatus.selector);
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_RevertsWhen_NoChangeInStatus_False() public {
        vm.startPrank(users.admin);

        // User is already false by default, trying to set false again should revert
        vm.expectRevert(FundMovementHelperUpgradeable.NoChangeInWhitelistStatus.selector);
        depositVault.whitelistFundTransferRecipient(recipient1, false);

        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_RevertsWhen_UnauthorizedUser() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert("UNAUTHORIZED");
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        vm.stopPrank();
    }

    function test_whitelistFundTransferRecipient_RevertsWhen_CalledByNonAdmin() public {
        vm.startPrank(users.alice);

        vm.expectRevert("UNAUTHORIZED");
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        vm.stopPrank();
    }

    // ========================================= removeFunds TESTS =========================================

    function test_removeFunds_Success_ValidTransfer() public {
        uint256 transferAmount = 1000e6;
        uint256 vaultBalanceBefore = usdc.balanceOf(address(depositVault));
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient1);

        vm.startPrank(users.admin);

        // Whitelist recipient first
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // Expect FundsRemoved event
        vm.expectEmit(true, true, true, true);
        emit FundMovementHelperUpgradeable.FundsRemoved(users.admin, address(usdc), transferAmount, recipient1);

        depositVault.removeFunds(transferAmount, recipient1);

        // Check balances
        assertEq(
            usdc.balanceOf(address(depositVault)), vaultBalanceBefore - transferAmount, "Vault balance should decrease"
        );
        assertEq(
            usdc.balanceOf(recipient1), recipientBalanceBefore + transferAmount, "Recipient balance should increase"
        );

        vm.stopPrank();
    }

    function test_removeFunds_Success_TransferFullBalance() public {
        uint256 vaultBalance = usdc.balanceOf(address(depositVault));
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient1);

        vm.startPrank(users.admin);

        // Whitelist recipient
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        depositVault.removeFunds(vaultBalance, recipient1);

        assertEq(usdc.balanceOf(address(depositVault)), 0, "Vault should have zero balance");
        assertEq(
            usdc.balanceOf(recipient1), recipientBalanceBefore + vaultBalance, "Recipient should receive full amount"
        );

        vm.stopPrank();
    }

    function test_removeFunds_Success_MultipleTransfers() public {
        uint256 transferAmount = 500e6;

        vm.startPrank(users.admin);

        // Whitelist both recipients
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        depositVault.whitelistFundTransferRecipient(recipient2, true);

        uint256 vaultBalanceInitial = usdc.balanceOf(address(depositVault));

        // Transfer to recipient1
        depositVault.removeFunds(transferAmount, recipient1);

        // Transfer to recipient2
        depositVault.removeFunds(transferAmount, recipient2);

        assertEq(
            usdc.balanceOf(address(depositVault)),
            vaultBalanceInitial - (2 * transferAmount),
            "Vault balance should decrease by total transfers"
        );
        assertEq(usdc.balanceOf(recipient1), transferAmount, "Recipient1 should receive correct amount");
        assertEq(usdc.balanceOf(recipient2), transferAmount, "Recipient2 should receive correct amount");

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_AmountIsZero() public {
        vm.startPrank(users.admin);

        // Whitelist recipient
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        vm.expectRevert(FundMovementHelperUpgradeable.AmountZero.selector);
        depositVault.removeFunds(0, recipient1);

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_RecipientNotWhitelisted() public {
        vm.startPrank(users.admin);

        vm.expectRevert(FundMovementHelperUpgradeable.RecipientNotWhitelisted.selector);
        depositVault.removeFunds(1000e6, recipient1);

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_InsufficientBalance() public {
        uint256 vaultBalance = usdc.balanceOf(address(depositVault));
        uint256 excessiveAmount = vaultBalance + 1000e6;

        vm.startPrank(users.admin);

        // Whitelist recipient
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // This should revert due to insufficient balance in the vault
        vm.expectRevert();
        depositVault.removeFunds(excessiveAmount, recipient1);

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_UnauthorizedUser() public {
        vm.startPrank(users.admin);
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        vm.stopPrank();

        vm.startPrank(unauthorizedUser);

        vm.expectRevert("UNAUTHORIZED");
        depositVault.removeFunds(1000e6, recipient1);

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_CalledByNonAdmin() public {
        vm.startPrank(users.admin);
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        vm.stopPrank();

        vm.startPrank(users.alice);

        vm.expectRevert("UNAUTHORIZED");
        depositVault.removeFunds(1000e6, recipient1);

        vm.stopPrank();
    }

    function test_removeFunds_RevertsWhen_RecipientRemovedFromWhitelist() public {
        vm.startPrank(users.admin);

        // First whitelist
        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // Then remove from whitelist
        depositVault.whitelistFundTransferRecipient(recipient1, false);

        // Now try to transfer - should fail
        vm.expectRevert(FundMovementHelperUpgradeable.RecipientNotWhitelisted.selector);
        depositVault.removeFunds(1000e6, recipient1);

        vm.stopPrank();
    }

    // ========================================= INTEGRATION TESTS =========================================

    function test_Integration_WhitelistAndRemoveFunds_Workflow() public {
        uint256 transferAmount = 2000e6;

        vm.startPrank(users.admin);

        // Step 1: Verify recipient is not whitelisted
        assertFalse(depositVault.isRecipientWhitelisted(recipient1));

        // Step 2: Whitelist recipient
        depositVault.whitelistFundTransferRecipient(recipient1, true);
        assertTrue(depositVault.isRecipientWhitelisted(recipient1));

        // Step 3: Remove funds successfully
        uint256 vaultBalanceBefore = usdc.balanceOf(address(depositVault));
        depositVault.removeFunds(transferAmount, recipient1);

        // Step 4: Verify transfer happened
        assertEq(usdc.balanceOf(address(depositVault)), vaultBalanceBefore - transferAmount);
        assertEq(usdc.balanceOf(recipient1), transferAmount);

        // Step 5: Remove from whitelist
        depositVault.whitelistFundTransferRecipient(recipient1, false);
        assertFalse(depositVault.isRecipientWhitelisted(recipient1));

        // Step 6: Verify can't transfer anymore
        vm.expectRevert(abi.encodeWithSignature("RecipientNotWhitelisted()"));
        depositVault.removeFunds(100e6, recipient1);

        vm.stopPrank();
    }

    function test_Integration_MultipleRecipientsManagement() public {
        vm.startPrank(users.admin);

        // Whitelist multiple recipients
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = users.alice;

        for (uint256 i = 0; i < recipients.length; i++) {
            depositVault.whitelistFundTransferRecipient(recipients[i], true);
            assertTrue(depositVault.isRecipientWhitelisted(recipients[i]));
        }

        // Transfer to each recipient
        uint256 transferAmount = 500e6;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 balanceBefore = usdc.balanceOf(recipients[i]);
            depositVault.removeFunds(transferAmount, recipients[i]);
            assertEq(usdc.balanceOf(recipients[i]), balanceBefore + transferAmount);
        }

        // Remove middle recipient from whitelist
        depositVault.whitelistFundTransferRecipient(recipient2, false);
        assertFalse(depositVault.isRecipientWhitelisted(recipient2));

        // Verify first and third still work
        depositVault.removeFunds(100e6, recipient1);
        depositVault.removeFunds(100e6, users.alice);

        // Verify middle recipient fails
        vm.expectRevert(abi.encodeWithSignature("RecipientNotWhitelisted()"));
        depositVault.removeFunds(100e6, recipient2);

        vm.stopPrank();
    }

    // ========================================= EDGE CASE TESTS =========================================

    function test_EdgeCase_WhitelistSelfAsRecipient() public {
        vm.startPrank(users.admin);

        // Admin whitelists themselves
        depositVault.whitelistFundTransferRecipient(users.admin, true);
        assertTrue(depositVault.isRecipientWhitelisted(users.admin));

        // Admin transfers to themselves
        uint256 balanceBefore = usdc.balanceOf(users.admin);
        uint256 transferAmount = 1000e6;

        depositVault.removeFunds(transferAmount, users.admin);

        assertEq(usdc.balanceOf(users.admin), balanceBefore + transferAmount);

        vm.stopPrank();
    }

    function test_EdgeCase_VaultAsRecipient() public {
        vm.startPrank(users.admin);

        // Whitelist the vault itself
        depositVault.whitelistFundTransferRecipient(address(depositVault), true);

        uint256 vaultBalanceBefore = usdc.balanceOf(address(depositVault));
        uint256 transferAmount = 1000e6;

        // This should work but result in no net change
        depositVault.removeFunds(transferAmount, address(depositVault));

        assertEq(usdc.balanceOf(address(depositVault)), vaultBalanceBefore);

        vm.stopPrank();
    }

    function test_EdgeCase_MaxUint256Transfer() public {
        vm.startPrank(users.admin);

        depositVault.whitelistFundTransferRecipient(recipient1, true);

        // This should revert due to insufficient balance
        vm.expectRevert();
        depositVault.removeFunds(type(uint256).max, recipient1);

        vm.stopPrank();
    }

    // ========================================= FUZZ TESTS =========================================

    function testFuzz_removeFunds_ValidAmounts(uint256 amount) public {
        // Bound the amount to reasonable values
        uint256 vaultBalance = usdc.balanceOf(address(depositVault));
        amount = bound(amount, 1, vaultBalance);

        vm.startPrank(users.admin);

        depositVault.whitelistFundTransferRecipient(recipient1, true);

        uint256 recipientBalanceBefore = usdc.balanceOf(recipient1);

        depositVault.removeFunds(amount, recipient1);

        assertEq(usdc.balanceOf(recipient1), recipientBalanceBefore + amount);

        vm.stopPrank();
    }

    function testFuzz_whitelistFundTransferRecipient_RandomAddresses(address randomRecipient) public {
        vm.assume(randomRecipient != address(0));

        vm.startPrank(users.admin);

        // Should be able to whitelist any address
        depositVault.whitelistFundTransferRecipient(randomRecipient, true);
        assertTrue(depositVault.isRecipientWhitelisted(randomRecipient));

        // Should be able to remove any address
        depositVault.whitelistFundTransferRecipient(randomRecipient, false);
        assertFalse(depositVault.isRecipientWhitelisted(randomRecipient));

        vm.stopPrank();
    }
}
