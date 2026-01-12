// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";

contract TestFulfillRedeem is BaseTest {
    uint256 internal amount = 100 * 1e6;
    uint256 internal aliceShares;

    function setUp() public override {
        BaseTest.setUp();
        vm.startPrank({msgSender: users.alice});

        depositVault.deposit(amount, users.alice);

        moveAssetsFromVault(amount);
        updateUnderlyingBalance(amount);

        vm.startPrank({msgSender: users.alice});
        aliceShares = depositVault.balanceOf(users.alice); // 100e6
        depositVault.requestRedeem(aliceShares, users.alice, users.alice);

        vm.roll(block.number + 1);
        usdc.transfer(address(depositVault), amount);
        updateUnderlyingBalance(0);
    }

    function testFulfillRedeemSuccess() public {
        vm.startPrank({msgSender: users.admin});
        uint256 usdcBalanceBefore = usdc.balanceOf(users.alice);
        uint256 totalPendingAssets = depositVault.totalPendingAssets(); // 100e6
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // 100e6, 100e6
        uint256 fee = 1e6;

        uint256 feeRecipientBalance = usdc.balanceOf(users.feeRecipient);

        {
            // Sanity check
            assertTrue(totalPendingAssets == amount, "Initial setup is incorrect");
            assertTrue(pendingAssets == amount, "Initial setup is incorrect");
            assertTrue(pendingShares == amount, "Initial setup is incorrect");
        }

        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);

        (uint256 pendingAssetsAfter, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice); //0, 0
        uint256 totalPendingAssetsAfter = depositVault.totalPendingAssets(); // 0

        uint256 usdcBalanceAfter = usdc.balanceOf(users.alice);

        assertEq(totalPendingAssetsAfter, totalPendingAssets - pendingAssets);
        assertEq(pendingAssetsAfter, 0);
        assertEq(pendingSharesAfter, 0);
        // assertEq(usdcBalanceAfter, usdcBalanceBefore + amount);
        assertEq(usdcBalanceBefore + amount - fee, usdcBalanceAfter);

        // verify that fee recipient received the funds
        assertEq(feeRecipientBalance + fee, usdc.balanceOf(users.feeRecipient));
    }

    function testFulfillRedeem__revertsOnZeroShares() public {
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSharesAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);
    }

    function testFulfillRedeem__revertsOnInvalidAmounts() public {
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSharesAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares + 1, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAssetsAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets + 1);
    }

    function testFulfillRedeem__revertsOnInsufficientAssets() public {
        moveAssetsFromVault(amount);
        vm.roll(block.number + 1);
        updateUnderlyingBalance(amount);
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);
    }
}
