// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";

contract TestMint is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
    }

    function test__mint__Reverts__WithSharesLessThanMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = 10e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = 5 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.DepositAmountLessThanThreshold.selector, shares, minDepositAmount)
        );
        depositVault.mint(shares, users.alice);

        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == aliceBalanceAfter, "Alice balance before and after is same");
    }

    function test__mint__Success__WithSharesEqualToMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = 100e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = 100 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function testMintSuccess() public {
        uint256 shares = 100 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function test__mint__success_onFirstDepositGreaterThanMinThresholdAmount() public {
        uint256 shares = 100 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), shares)));
        depositVault.mint(shares, users.alice);

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares, "Alice balance after is not the amount");
    }

    function test__mint__success_onDepositGreaterThanMinThresholdAmount() public {
        uint256 shares = 100 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        // mint 100 shares for 100 usdc
        vm.startPrank(users.alice);
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        // add some usdc to deposit vault
        // price of 1 share is 2 usdc
        deal(address(usdc), address(depositVault), 200e6);

        // ensure vault has 200 usdc
        assertEq(usdc.balanceOf(address(depositVault)), 200e6, "deposit vault usdc balance should 200e6");
        // ensure totalAssets is 200e6 usdc
        assertEq(depositVault.totalAssets(), 200e6, "total assets should be 200e6");
        // ensure totalSupply is 100e6
        assertEq(depositVault.totalSupply(), 100e6, "total supply should be 100e6");

        vm.startPrank(users.alice);
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), 200e6)));
        depositVault.mint(shares, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == shares * 2, "Alice vault balance should be twice the amount of shares");
    }
}
