// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/libraries/Errors.sol";

contract TestCancelRedeem is BaseTest {
    using Math for uint256;

    uint256 internal amount = 100 * 1e6;
    uint256 internal aliceShares;

    function setUp() public override {
        BaseTest.setUp();
        vm.startPrank({msgSender: users.alice});

        depositVault.deposit(amount, users.alice);

        moveAssetsFromVault(amount);
        updateUnderlyingBalance(amount);

        vm.startPrank({msgSender: users.alice});
        aliceShares = depositVault.balanceOf(users.alice);
        depositVault.requestRedeem(aliceShares, users.alice, users.alice);

        vm.roll(block.number + 1);
        usdc.transfer(address(depositVault), amount);
        updateUnderlyingBalance(0);
    }

    function testCancelRedeem() public {
        uint256 totalPendingAssets = depositVault.totalPendingAssets(); // 100e6
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // 100e6, 100e6
        uint256 aliceSharesBefore = depositVault.balanceOf(users.alice); // 0

        vm.startPrank({msgSender: users.admin});
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);

        uint256 totalPendingAssetsAfter = depositVault.totalPendingAssets(); // 0
        (uint256 pendingAssetsAfter, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice); // 0, 0
        uint256 aliceSharesAfter = depositVault.balanceOf(users.alice); //100e6

        // sanity check
        assertEq(totalPendingAssets, 100e6);
        assertEq(pendingAssets, 100e6);
        assertEq(pendingShares, 100e6);
        assertEq(aliceSharesBefore, 0);
        assertEq(totalPendingAssetsAfter, 0);
        assertEq(pendingAssetsAfter, 0);
        assertEq(pendingSharesAfter, 0);
        assertEq(aliceSharesAfter, 100e6);

        assertTrue(
            totalPendingAssetsAfter == totalPendingAssets - pendingShares,
            "Total pending assets after is not the difference"
        );
        assertTrue(pendingAssetsAfter == 0, "Pending assets after is not 0");
        assertTrue(pendingSharesAfter == 0, "Pending shares after is not 0");
        assertEq(aliceSharesAfter, aliceSharesBefore + pendingShares, "Alice did not receive the pending shares back");
    }

    function testCancelRedeem__revertsOnInvalidAmounts() public {
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // 10e6

        vm.startPrank({msgSender: users.admin});

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSharesAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares + 1, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAssetsAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets + 1);
    }

    function testCancelRedeemOnDoubleCancel() public {
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);

        vm.startPrank({msgSender: users.admin});
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSharesAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);
    }
}
