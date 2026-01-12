// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

contract TestRemoveFunds is VaultFundManagerBase {
    event RemoveFunds(address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        vm.startPrank(users.admin);
        MockAuthority auth = MockAuthority(address(authority));
        auth.setRoleCapability(
            ADMIN_ROLE, address(fundManager), fundManager.removeFunds.selector, true
        );
        vm.stopPrank();

        // Fund the fund manager contract with tokens for testing
        deal({token: address(token), to: address(fundManager), give: INITIAL_DEPOSIT, adjust: true});
    }

    function test_RemoveFunds_RevertsWhenNotCalledByVault() public {
        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.removeFunds(recipient1, TEST_TRANSFER_AMOUNT);
    }

    function test_RemoveFunds_RevertsWithZeroRecipient() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            address(0),
            TEST_TRANSFER_AMOUNT
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFunds_RevertsWithZeroAmount() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            0
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.ZeroAmount.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFunds_RevertsWithInsufficientBalance() public {
        uint256 contractBalance = token.balanceOf(address(fundManager));
        uint256 excessiveAmount = contractBalance + 1;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            excessiveAmount
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.InsufficientBalance.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFunds_RevertsCalledByUserAuthorizedToCallManageButUnAuthorisedToCallRemoveFunds() public {
        uint256 transferAmount = getQuantizedValue(30_000);
        uint256 initialContractBalance = token.balanceOf(address(fundManager));
        uint256 initialRecipientBalance = token.balanceOf(recipient1);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.alice);
        // TargetMethodNotAuthorized(0xefdD6592Dec5675679D3808C02c82F97c5B9F809, 0x50d6368c)
        vm.expectRevert(abi.encodeWithSignature("TargetMethodNotAuthorized(address,bytes4)", address(fundManager), bytes4(fundManager.removeFunds.selector)));
        vault.manage(address(fundManager), data, 0);

        // Check balances
        assertEq(token.balanceOf(address(fundManager)), initialContractBalance);
        assertEq(token.balanceOf(recipient1), initialRecipientBalance);
    }

    function test_RemoveFunds_RevertsCalledByUserAuthorizedToCallManage() public {
        uint256 transferAmount = getQuantizedValue(30_000);
        uint256 initialContractBalance = token.balanceOf(address(fundManager));
        uint256 initialRecipientBalance = token.balanceOf(recipient1);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.bob);
        vm.expectRevert("UNAUTHORIZED");
        vault.manage(address(fundManager), data, 0);

        // Check balances
        assertEq(token.balanceOf(address(fundManager)), initialContractBalance);
        assertEq(token.balanceOf(recipient1), initialRecipientBalance);
    }

    function test_RemoveFunds_Success() public {
        uint256 transferAmount = getQuantizedValue(30_000);
        uint256 initialContractBalance = token.balanceOf(address(fundManager));
        uint256 initialRecipientBalance = token.balanceOf(recipient1);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Check balances
        assertEq(token.balanceOf(address(fundManager)), initialContractBalance - transferAmount);
        assertEq(token.balanceOf(recipient1), initialRecipientBalance + transferAmount);
    }

    function test_RemoveFunds_EmitsCorrectEvent() public {
        uint256 transferAmount = getQuantizedValue(25_000);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.expectEmit(true, true, true, true);
        emit RemoveFunds(recipient1, transferAmount);

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFunds_WithMaximumAmount() public {
        uint256 contractBalance = token.balanceOf(address(fundManager));
        uint256 initialRecipientBalance = token.balanceOf(recipient1);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            contractBalance
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Contract should have zero balance
        assertEq(token.balanceOf(address(fundManager)), 0);

        // Recipient should receive full amount
        assertEq(token.balanceOf(recipient1), initialRecipientBalance + contractBalance);
    }

    function test_RemoveFunds_MultipleTransfers() public {
        uint256 firstTransfer = getQuantizedValue(20_000);
        uint256 secondTransfer = getQuantizedValue(15_000);
        uint256 initialContractBalance = token.balanceOf(address(fundManager));

        // First transfer to recipient1
        bytes memory data1 = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            firstTransfer
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data1, 0);

        // Second transfer to recipient2
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient2,
            secondTransfer
        );

        vault.manage(address(fundManager), data2, 0);

        // Check final state
        assertEq(token.balanceOf(recipient1), firstTransfer);
        assertEq(token.balanceOf(recipient2), secondTransfer);
        assertEq(token.balanceOf(address(fundManager)), initialContractBalance - firstTransfer - secondTransfer);
    }

    function test_RemoveFunds_WithDifferentInitiators() public {
        uint256 transferAmount = getQuantizedValue(10_000);

        // First transfer initiated by admin
        bytes memory data1 = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.expectEmit(true, true, true, true);
        emit RemoveFunds(recipient1, transferAmount);

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data1, 0);

        // Second transfer initiated by admin
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient2,
            transferAmount
        );

        vm.expectEmit(true, true, true, true);
        emit RemoveFunds(recipient2, transferAmount);

        vault.manage(address(fundManager), data2, 0);

        // Check both transfers succeeded
        assertEq(token.balanceOf(recipient1), transferAmount);
        assertEq(token.balanceOf(recipient2), transferAmount);
    }

    function test_RemoveFunds_DoesNotAffectVaultBalances() public {
        uint256 transferAmount = getQuantizedValue(40_000);
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialVaultAggregatedBalance = vault.aggregatedUnderlyingBalances();
        uint256 initialVaultTotalAssets = vault.totalAssets();

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Vault balances should remain unchanged
        assertEq(token.balanceOf(address(vault)), initialVaultBalance);
        assertEq(vault.aggregatedUnderlyingBalances(), initialVaultAggregatedBalance);
        assertEq(vault.totalAssets(), initialVaultTotalAssets);
    }

    function test_RemoveFunds_WithExactBalance() public {
        uint256 contractBalance = token.balanceOf(address(fundManager));
        
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            contractBalance
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Contract should have exactly zero balance
        assertEq(token.balanceOf(address(fundManager)), 0);
        assertEq(token.balanceOf(recipient1), contractBalance);
    }


    function test_RemoveFunds_SmallAmount() public {
        uint256 smallAmount = 1; // 1 wei of tokens

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            smallAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        assertEq(token.balanceOf(recipient1), smallAmount);
    }

    function test_RemoveFunds_LargeAmount() public {
        // First add more funds to the contract
        uint256 largeAmount = getQuantizedValue(500_000); // 500K tokens
        deal({token: address(token), to: address(fundManager), give: largeAmount, adjust: true});

        uint256 transferAmount = getQuantizedValue(400_000); // 400K tokens
        uint256 initialContractBalance = token.balanceOf(address(fundManager));

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        assertEq(token.balanceOf(address(fundManager)), initialContractBalance - transferAmount);
        assertEq(token.balanceOf(recipient1), transferAmount);
    }
}