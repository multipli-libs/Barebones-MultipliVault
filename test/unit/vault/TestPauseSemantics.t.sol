// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Regression tests for the pause semantics of MultipliVault.
//
// Design intent (see `MultipliVault._update`):
// - While paused, redemption fulfillment, cancellation, and admin mint/burn
//   MUST stay live so redemption liveness is preserved in black-swan events
//   (this was previously broken: the old `whenNotPaused` gate on `_update`
//   made `fulfillRedeem`/`cancelRedeem`/`adminMint` revert while paused).
// - While paused, plain share-holder-to-share-holder transfers MUST keep
//   reverting, and user-facing entry points (deposit/mint/requestredeem)
//   remain gated by `whenNotPaused`.

import {BaseTest} from "./Base.t.sol";

contract TestPauseSemantics is BaseTest {
    uint256 internal amount;
    uint256 internal aliceShares;

    function setUp() public override {
        BaseTest.setUp();

        amount = 100 * getQuantizedValue(1);
        vm.startPrank({msgSender: users.alice});

        depositVault.deposit(amount, users.alice);

        moveAssetsFromVault(amount);
        updateUnderlyingBalance(amount);

        vm.startPrank({msgSender: users.alice});
        aliceShares = depositVault.balanceOf(users.alice);
        depositVault.requestRedeem(aliceShares, users.alice, users.alice);

        vm.roll(block.number + 1);
        token.transfer(address(depositVault), amount);
        updateUnderlyingBalance(0);

        // Pause the vault after a normal redemption request is pending, i.e.
        // the black-swan scenario that the pause mechanism is designed for.
        vm.startPrank({msgSender: users.admin});
        depositVault.pause();
        assertTrue(depositVault.paused(), "Vault was not paused in setUp.");
        vm.stopPrank();
    }

    function testFulfillRedeem_SucceedsWhilePaused() public {
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) =
            depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingShares, aliceShares, "Setup pending state is incorrect.");

        uint256 fee = getQuantizedValue(1);
        uint256 tokenBalanceBefore = token.balanceOf(users.alice);

        // This call previously reverted with EnforcedPause: the fulfillment
        // path is now allowed to run while paused.
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);

        assertEq(
            token.balanceOf(users.alice), tokenBalanceBefore + amount - fee,
            "Receiver should receive assets minus the withdrawal fee while paused."
        );
        (, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingSharesAfter, 0, "Pending redemption should be cleared while paused.");
    }

    function testCancelRedeem_SucceedsWhilePaused() public {
        vm.startPrank({msgSender: users.admin});
        (, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);

        // Cancellation returns shares to the receiver even while paused.
        depositVault.cancelRedeem(users.alice, pendingShares, amount);

        assertEq(
            depositVault.balanceOf(users.alice), aliceShares,
            "Shares should be returned to the owner on cancellation while paused."
        );
        (, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingSharesAfter, 0, "Pending redemption should be cleared on cancellation.");
    }

    function testAdminMint_SucceedsWhilePaused() public {
        vm.startPrank({msgSender: users.admin});
        uint256 mintAmount = getQuantizedValue(1);
        uint256 bobBalanceBefore = depositVault.balanceOf(users.bob);

        depositVault.adminMint(users.bob, mintAmount);

        assertEq(
            depositVault.balanceOf(users.bob), bobBalanceBefore + mintAmount,
            "adminMint should work while the contract is paused (per NatSpec)."
        );
    }

    function testPlainShareTransfer_RevertsWhilePaused() public {
        vm.startPrank({msgSender: users.alice});

        // Share transfers between plain holders stay frozen while paused.
        vm.expectRevert();
        depositVault.transfer(users.bob, aliceShares);
    }

    function testDeposit_RevertsWhilePaused() public {
        vm.startPrank({msgSender: users.bob});

        token.approve(address(depositVault), amount);

        // Deposit is a user-facing entry point and remains gated by
        // `whenNotPaused`.
        vm.expectRevert();
        depositVault.deposit(amount, users.bob);

        vm.stopPrank();
    }

    function testUnpause_RestoresNormalTransferFlow() public {
        vm.startPrank({msgSender: users.admin});
        depositVault.unpause();
        vm.stopPrank();

        // Note: alice's shares are fully escrowed by the pending redemption
        // request from setUp, so mint fresh shares via adminMint first.
        vm.startPrank({msgSender: users.admin});
        depositVault.adminMint(users.bob, getQuantizedValue(1));
        vm.stopPrank();

        vm.startPrank({msgSender: users.bob});
        assertTrue(depositVault.transfer(users.alice, 1), "Transfer should work again after unpause.");
    }
}
