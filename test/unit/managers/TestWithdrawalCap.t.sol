// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";
import {MockAuthority} from "test/mocks/MockAuthority.sol";

contract TestWithdrawalCap is VaultFundManagerBase {
    event WithdrawalCapUpdated(uint256 oldCap, uint256 newCap);

    uint256 internal CAP_AMOUNT;

    function setUp() public override {
        super.setUp();

        CAP_AMOUNT = getQuantizedValue(10_000); // 10K cap per epoch

        // Deposit funds into vault for testing
        depositForUser(users.alice, INITIAL_DEPOSIT);

        // Set up permission for setMaxWithdrawalPerEpoch via manage
        vm.startPrank(users.admin);
        MockAuthority(address(authority)).setRoleCapability(
            FUND_MANAGER_ROLE,
            address(fundManager),
            fundManager.setMaxWithdrawalPerEpoch.selector,
            true
        );

        // Also need removeFunds permission
        MockAuthority(address(authority)).setRoleCapability(
            FUND_MANAGER_ROLE,
            address(fundManager),
            fundManager.removeFunds.selector,
            true
        );
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    //  setMaxWithdrawalPerEpoch
    // ──────────────────────────────────────────────

    function test_setMaxWithdrawalPerEpoch_Success() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.setMaxWithdrawalPerEpoch.selector, CAP_AMOUNT
        );

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.maxWithdrawalPerEpoch(), CAP_AMOUNT);
    }

    function test_setMaxWithdrawalPerEpoch_EmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(
            fundManager.setMaxWithdrawalPerEpoch.selector, CAP_AMOUNT
        );

        vm.expectEmit(true, true, true, true);
        emit WithdrawalCapUpdated(0, CAP_AMOUNT);

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);
    }

    function test_setMaxWithdrawalPerEpoch_RevertsWhenNotCalledByVault() public {
        vm.prank(users.alice);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.setMaxWithdrawalPerEpoch(CAP_AMOUNT);
    }

    function test_setMaxWithdrawalPerEpoch_CanSetToZero() public {
        // First set a cap
        _setCap(CAP_AMOUNT);
        assertEq(fundManager.maxWithdrawalPerEpoch(), CAP_AMOUNT);

        // Then disable it
        _setCap(0);
        assertEq(fundManager.maxWithdrawalPerEpoch(), 0);
    }

    function test_setMaxWithdrawalPerEpoch_CanUpdate() public {
        _setCap(CAP_AMOUNT);

        uint256 newCap = getQuantizedValue(20_000);

        bytes memory data = abi.encodeWithSelector(
            fundManager.setMaxWithdrawalPerEpoch.selector, newCap
        );

        vm.expectEmit(true, true, true, true);
        emit WithdrawalCapUpdated(CAP_AMOUNT, newCap);

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.maxWithdrawalPerEpoch(), newCap);
    }

    // ──────────────────────────────────────────────
    //  Withdrawal cap enforcement on removeFundsFromVault
    // ──────────────────────────────────────────────

    function test_removeFundsFromVault_WithCapEnabled_Success() public {
        _setCap(CAP_AMOUNT);

        uint256 withdrawAmount = getQuantizedValue(5_000); // under cap

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, withdrawAmount
        );

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.currentEpochWithdrawals(), withdrawAmount);
    }

    function test_removeFundsFromVault_WithCapEnabled_ExactCap() public {
        _setCap(CAP_AMOUNT);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, CAP_AMOUNT
        );

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.currentEpochWithdrawals(), CAP_AMOUNT);
    }

    function test_removeFundsFromVault_RevertsWhenCapExceeded() public {
        _setCap(CAP_AMOUNT);

        uint256 overCapAmount = CAP_AMOUNT + 1;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, overCapAmount
        );

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFundManager.VaultFundManager__WithdrawalCapExceeded.selector,
                overCapAmount,
                CAP_AMOUNT
            )
        );
        vault.manage(address(fundManager), data, 0);
    }

    function test_removeFundsFromVault_CumulativeCapEnforcement() public {
        _setCap(CAP_AMOUNT);

        uint256 first = getQuantizedValue(6_000);
        uint256 second = getQuantizedValue(5_000); // 6K + 5K = 11K > 10K cap

        // First withdrawal succeeds
        bytes memory data1 = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, first
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data1, 0);
        vm.roll(block.number + 1); // avoid same-block revert

        // Second withdrawal exceeds cumulative cap
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient2, second
        );

        uint256 remaining = CAP_AMOUNT - first;

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFundManager.VaultFundManager__WithdrawalCapExceeded.selector,
                second,
                remaining
            )
        );
        vault.manage(address(fundManager), data2, 0);
    }

    function test_removeFundsFromVault_EpochResetsAfter24Hours() public {
        _setCap(CAP_AMOUNT);

        // Use full cap
        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, CAP_AMOUNT
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.currentEpochWithdrawals(), CAP_AMOUNT);

        // Warp 24 hours + 1 second
        vm.warp(block.timestamp + 24 hours + 1);
        vm.roll(block.number + 1);

        // Should work again — epoch reset
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient2, CAP_AMOUNT
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data2, 0);

        // Epoch counter should reflect only the new withdrawal
        assertEq(fundManager.currentEpochWithdrawals(), CAP_AMOUNT);
    }

    function test_removeFundsFromVault_EpochDoesNotResetBefore24Hours() public {
        _setCap(CAP_AMOUNT);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, CAP_AMOUNT
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Warp to exactly 24 hours (not past)
        vm.warp(fundManager.lastEpochReset() + 24 hours);
        vm.roll(block.number + 1);

        // Should still revert — epoch not yet reset (needs > 24 hours)
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient2, 1
        );
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFundManager.VaultFundManager__WithdrawalCapExceeded.selector,
                1,
                0
            )
        );
        vault.manage(address(fundManager), data2, 0);
    }

    function test_removeFundsFromVault_NoCapWhenZero() public {
        // Cap is 0 by default — should allow any amount
        assertEq(fundManager.maxWithdrawalPerEpoch(), 0);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, INITIAL_DEPOSIT
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Withdrawals counter stays 0 when cap is disabled
        assertEq(fundManager.currentEpochWithdrawals(), 0);
    }

    // ──────────────────────────────────────────────
    //  Withdrawal cap enforcement on removeFunds
    // ──────────────────────────────────────────────

    function test_removeFunds_WithCapEnabled_Success() public {
        _setCap(CAP_AMOUNT);

        uint256 withdrawAmount = getQuantizedValue(5_000);

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector, recipient1, withdrawAmount
        );

        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(fundManager.currentEpochWithdrawals(), withdrawAmount);
    }

    function test_removeFunds_RevertsWhenCapExceeded() public {
        _setCap(CAP_AMOUNT);

        uint256 overCapAmount = CAP_AMOUNT + 1;

        bytes memory data = abi.encodeWithSelector(
            fundManager.removeFunds.selector, recipient1, overCapAmount
        );

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFundManager.VaultFundManager__WithdrawalCapExceeded.selector,
                overCapAmount,
                CAP_AMOUNT
            )
        );
        vault.manage(address(fundManager), data, 0);
    }

    function test_removeFunds_SharedEpochCounter() public {
        _setCap(CAP_AMOUNT);

        uint256 half = CAP_AMOUNT / 2;

        // removeFundsFromVault uses half the cap
        bytes memory data1 = abi.encodeWithSelector(
            fundManager.removeFundsFromVault.selector, recipient1, half
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data1, 0);

        vm.roll(block.number + 1);

        // removeFunds tries to use more than the remaining cap
        uint256 overRemaining = half + 1;
        bytes memory data2 = abi.encodeWithSelector(
            fundManager.removeFunds.selector, recipient2, overRemaining
        );

        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFundManager.VaultFundManager__WithdrawalCapExceeded.selector,
                overRemaining,
                half
            )
        );
        vault.manage(address(fundManager), data2, 0);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _setCap(uint256 cap) internal {
        bytes memory data = abi.encodeWithSelector(
            fundManager.setMaxWithdrawalPerEpoch.selector, cap
        );
        vm.prank(users.alice);
        vault.manage(address(fundManager), data, 0);
    }
}
