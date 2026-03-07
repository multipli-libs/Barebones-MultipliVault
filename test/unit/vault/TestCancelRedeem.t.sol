// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/libraries/Errors.sol";

contract TestCancelRedeem is BaseTest {
    using Math for uint256;

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
    }

    function testCancelRedeem() public {
        uint256 totalPendingAssets = depositVault.totalPendingAssets(); // getQuantizedValue(100);
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // getQuantizedValue(100), getQuantizedValue(100);
        uint256 aliceSharesBefore = depositVault.balanceOf(users.alice); // 0

        vm.startPrank({msgSender: users.admin});
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);

        uint256 totalPendingAssetsAfter = depositVault.totalPendingAssets(); // 0
        (uint256 pendingAssetsAfter, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice); // 0, 0
        uint256 aliceSharesAfter = depositVault.balanceOf(users.alice); //getQuantizedValue(100);

        // sanity check
        assertEq(totalPendingAssets, getQuantizedValue(100));
        assertEq(pendingAssets, getQuantizedValue(100));
        assertEq(pendingShares, getQuantizedValue(100));
        assertEq(aliceSharesBefore, 0);
        assertEq(totalPendingAssetsAfter, 0);
        assertEq(pendingAssetsAfter, 0);
        assertEq(pendingSharesAfter, 0);
        assertEq(aliceSharesAfter, getQuantizedValue(100));

        assertTrue(
            totalPendingAssetsAfter == totalPendingAssets - pendingShares,
            "Total pending assets after is not the difference"
        );
        assertTrue(pendingAssetsAfter == 0, "Pending assets after is not 0");
        assertTrue(pendingSharesAfter == 0, "Pending shares after is not 0");
        assertEq(aliceSharesAfter, aliceSharesBefore + pendingShares, "Alice did not receive the pending shares back");
    }

    function testCancelRedeem__revertsOnInvalidAmounts() public {
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // getQuantizedValue(10);

        vm.startPrank({msgSender: users.admin});

        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares + 1, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidAssetsAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets + 1);
    }

    function testCancelRedeemOnDoubleCancel() public {
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);

        vm.startPrank({msgSender: users.admin});
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        depositVault.cancelRedeem(users.alice, pendingShares, pendingAssets);
    }
}
