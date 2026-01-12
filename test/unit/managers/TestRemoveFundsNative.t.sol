// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

contract TestRemoveFundsNative is VaultFundManagerBase {
    event RemoveFundsNative(address indexed to, uint256 amount);

    uint256 internal constant NATIVE_BALANCE = 10 ether; // 10 AVAX
    uint256 internal constant TEST_NATIVE_AMOUNT = 5 ether; // 5 AVAX

    function setUp() public override {
        super.setUp();

        vm.startPrank(users.admin);
        MockAuthority auth = MockAuthority(address(authority));
        auth.setRoleCapability(
            ADMIN_ROLE, address(fundManager), fundManager.removeFundsNative.selector, true
        );
        vm.stopPrank();

        // Fund the fund manager contract with native AVAX for testing
        vm.deal(address(fundManager), NATIVE_BALANCE);
    }

    function test_RemoveFundsNative_RevertsWhenNotCalledByVault() public {
        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.removeFundsNative(recipient1, TEST_NATIVE_AMOUNT);
    }

    function test_RemoveFundsNative_RevertsWithZeroRecipient() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            address(0),
            TEST_NATIVE_AMOUNT
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsNative_RevertsWithZeroAmount() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            0
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.ZeroAmount.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsNative_RevertsWithInsufficientBalance() public {
        uint256 contractBalance = address(fundManager).balance;
        uint256 excessiveAmount = contractBalance + 1 ether;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            excessiveAmount
        );

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.InsufficientBalance.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsNative_RevertsCalledByUserAuthorizedToCallManageButUnAuthorisedToCallRemoveFundsNative() public {
        uint256 transferAmount = 3 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 initialRecipientBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("TargetMethodNotAuthorized(address,bytes4)", address(fundManager), bytes4(fundManager.removeFundsNative.selector)));
        vault.manage(address(fundManager), data, 0);

        // Check balances remain unchanged
        assertEq(address(fundManager).balance, initialContractBalance);
        assertEq(recipient1.balance, initialRecipientBalance);
    }

    function test_RemoveFundsNative_RevertsCalledByUserUnauthorizedToCallManage() public {
        uint256 transferAmount = 3 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 initialRecipientBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.bob);
        vm.expectRevert("UNAUTHORIZED");
        vault.manage(address(fundManager), data, 0);

        // Check balances remain unchanged
        assertEq(address(fundManager).balance, initialContractBalance);
        assertEq(recipient1.balance, initialRecipientBalance);
    }

    function test_RemoveFundsNative_Success() public {
        uint256 transferAmount = 3 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 initialRecipientBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Check balances
        assertEq(address(fundManager).balance, initialContractBalance - transferAmount);
        assertEq(recipient1.balance, initialRecipientBalance + transferAmount);
    }

    function test_RemoveFundsNative_EmitsCorrectEvent() public {
        uint256 transferAmount = 2 ether;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.expectEmit(true, true, true, true);
        emit RemoveFundsNative(recipient1, transferAmount);

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsNative_WithMaximumAmount() public {
        uint256 contractBalance = address(fundManager).balance;
        uint256 initialRecipientBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            contractBalance
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Contract should have zero balance
        assertEq(address(fundManager).balance, 0);

        // Recipient should receive full amount
        assertEq(recipient1.balance, initialRecipientBalance + contractBalance);
    }

    function test_RemoveFundsNative_MultipleTransfers() public {
        uint256 firstTransfer = 2 ether;
        uint256 secondTransfer = 1.5 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 recipientOldBalance1 = recipient1.balance;
        uint256 recipientOldBalance2 = recipient2.balance;

        // First transfer to recipient1
        bytes memory data1 = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            firstTransfer
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data1, 0);

        // Second transfer to recipient2
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient2,
            secondTransfer
        );

        vault.manage(address(fundManager), data2, 0);

        // Check final state
        assertEq(recipient1.balance - recipientOldBalance1, firstTransfer);
        assertEq(recipient2.balance - recipientOldBalance2, secondTransfer);
        assertEq(address(fundManager).balance, initialContractBalance - firstTransfer - secondTransfer);
    }

    function test_RemoveFundsNative_DoesNotAffectVaultBalances() public {
        uint256 transferAmount = 4 ether;
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialVaultAggregatedBalance = vault.aggregatedUnderlyingBalances();
        uint256 initialVaultTotalAssets = vault.totalAssets();

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
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

    function test_RemoveFundsNative_WithExactBalance() public {
        uint256 contractBalance = address(fundManager).balance;
        uint256 recipientOldBalance = recipient1.balance;
        
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            contractBalance
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        // Contract should have exactly zero balance
        assertEq(address(fundManager).balance, 0);
        assertEq(recipient1.balance - recipientOldBalance, contractBalance);
    }

    function test_RemoveFundsNative_SmallAmount() public {
        uint256 smallAmount = 1 wei;
        uint256 recipientOldBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            smallAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        assertEq(recipient1.balance - recipientOldBalance, smallAmount);
    }

    function test_RemoveFundsNative_LargeAmount() public {
        // First add more AVAX to the contract
        uint256 largeBalance = 50 ether;
        vm.deal(address(fundManager), largeBalance);

        uint256 transferAmount = 40 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 recipientOldBalance = recipient1.balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        assertEq(address(fundManager).balance, initialContractBalance - transferAmount);
        assertEq(recipient1.balance - recipientOldBalance, transferAmount);
    }

    function test_RemoveFundsNative_TransferFailureScenario() public {
        // Create a contract that rejects AVAX transfers
        RejectingReceiver rejectingContract = new RejectingReceiver();
        
        uint256 transferAmount = 1 ether;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            address(rejectingContract),
            transferAmount
        );

        vm.startPrank(users.admin);
        vm.expectRevert("Transfer failed");
        vault.manage(address(fundManager), data, 0);
    }

    function test_RemoveFundsNative_SuccessfulContractRecipient() public {
        // Create a contract that accepts AVAX transfers
        AcceptingReceiver acceptingContract = new AcceptingReceiver();
        
        uint256 transferAmount = 1 ether;
        uint256 initialContractBalance = address(fundManager).balance;
        uint256 oldAcceptingContractBalance = address(acceptingContract).balance;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            address(acceptingContract),
            transferAmount
        );

        vm.startPrank(users.admin);
        vault.manage(address(fundManager), data, 0);

        assertEq(address(fundManager).balance, initialContractBalance - transferAmount);
        assertEq(address(acceptingContract).balance - oldAcceptingContractBalance, transferAmount);
    }

    function test_RemoveFundsNative_GasEstimation() public {
        uint256 transferAmount = 1 ether;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsNative.selector,
            recipient1,
            transferAmount
        );

        vm.startPrank(users.admin);
        
        uint256 gasBefore = gasleft();
        vault.manage(address(fundManager), data, 0);
        uint256 gasAfter = gasleft();
        
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Ensure gas usage is reasonable (less than 100k gas)
        assertLt(gasUsed, 100_000, "Gas usage should be reasonable");
    }
}

// Helper contracts for testing transfer scenarios
contract RejectingReceiver {
    // This contract rejects all AVAX transfers
    receive() external payable {
        revert("Rejecting transfer");
    }
}

contract AcceptingReceiver {
    // This contract accepts AVAX transfers
    receive() external payable {
        // Accept the transfer silently
    }
}