// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestRequestRedeem is BaseTest {
    using Math for uint256;

    uint256 internal amount;

    function setUp() public override {
        BaseTest.setUp();
        amount = 100 * getQuantizedValue(1);
        vm.startPrank({msgSender: users.alice});
        depositVault.deposit(amount, users.alice);
    }

    function testRequestRedeemIsSuccess() public {
        uint256 aliceShares = depositVault.balanceOf(users.alice);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        uint256 totalAssetsBefore = depositVault.totalAssets();
        assertTrue(aliceBalanceBefore == amount, "Alice balance before is not the amount");
        assertTrue(totalAssetsBefore == amount, "Total assets before is not the amount");

        depositVault.requestRedeem(aliceShares, users.alice, users.alice);

        uint256 aliceSharesAfter = depositVault.balanceOf(users.alice); //0
        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice); // 0
        uint256 totalAssetsAfter = depositVault.totalAssets(); // 100
        assertTrue(aliceSharesAfter == 0, "Alice shares after is not 0");
        assertTrue(aliceBalanceAfter == 0, "Alice balance after is not 0");
        assertTrue(totalAssetsAfter == totalAssetsBefore, "Total asset before != total assets after");
    }

    function testRequestRedeem__revertsWhenSharesAmountIsZero() public {
        uint256 aliceShares = depositVault.balanceOf(users.alice);
        assertTrue(aliceShares == amount, "Alice shares is not the amount");

        vm.expectRevert(abi.encodeWithSelector(Errors.SharesAmountZero.selector));
        depositVault.requestRedeem(0, users.alice, users.alice);
    }

    function testRequestRedeem__revertsWhenInitiatedByNonOwner() public {
        uint256 aliceShares = depositVault.balanceOf(users.alice);
        assertTrue(aliceShares == amount, "Alice shares is not the amount");

        vm.expectRevert(abi.encodeWithSelector(Errors.NotSharesOwner.selector));
        depositVault.requestRedeem(aliceShares, users.alice, users.bob);
    }

    function testRequestRedeem__revertsOnInsufficientShares() public {
        uint256 aliceShares = depositVault.balanceOf(users.alice);
        assertTrue(aliceShares == amount, "Alice shares is not the amount");

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientShares.selector));
        depositVault.requestRedeem(aliceShares + 1, users.alice, users.alice);
    }
}
