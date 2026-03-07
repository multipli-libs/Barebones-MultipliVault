// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";

contract TestMint is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
    }

    function test__mint__Reverts__WithSharesLessThanMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(10);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = 5 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__DepositAmountLessThanThreshold.selector, shares, minDepositAmount)
        );
        depositVault.mint(shares, users.alice);

        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == aliceBalanceAfter, "Alice balance before and after is same");
    }

    function test__mint__Success__WithSharesEqualToMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(100);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = 100 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function testMintSuccess() public {
        uint256 shares = 100 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function test__mint__success_onFirstDepositGreaterThanMinThresholdAmount() public {
        uint256 shares = 100 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function test__mint__success_onDepositGreaterThanMinThresholdAmount() public {
        uint256 shares = 100 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        // mint 100 shares for 100 token
        vm.startPrank(users.alice);
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        // add some token to deposit vault
        // price of 1 share is 2 token
        deal(address(token), address(depositVault), getQuantizedValue(200));

        // ensure vault has 200 token
        assertEq(token.balanceOf(address(depositVault)), getQuantizedValue(200), "deposit vault token balance should getQuantizedValue(200);");
        // ensure totalAssets is getQuantizedValue(200); token
        assertEq(depositVault.totalAssets(), getQuantizedValue(200), "total assets should be getQuantizedValue(200);");
        // ensure totalSupply is getQuantizedValue(100);
        assertEq(depositVault.totalSupply(), getQuantizedValue(100), "total supply should be getQuantizedValue(100);");

        vm.startPrank(users.alice);
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), getQuantizedValue(200))));
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares * 2, "Alice vault balance should be twice the amount of shares");
    }
}
