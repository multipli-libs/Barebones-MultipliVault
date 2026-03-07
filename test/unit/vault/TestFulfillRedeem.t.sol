// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";


contract TestFulfillRedeem is BaseTest {
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
        aliceShares = depositVault.balanceOf(users.alice); // getQuantizedValue(100);
        depositVault.requestRedeem(aliceShares, users.alice, users.alice);

        vm.roll(block.number + 1);
        token.transfer(address(depositVault), amount);
        updateUnderlyingBalance(0);
    }

    function testFulfillRedeemSuccess() public {
        vm.startPrank({msgSender: users.admin});
        uint256 tokenBalanceBefore = token.balanceOf(users.alice);
        uint256 totalPendingAssets = depositVault.totalPendingAssets(); // getQuantizedValue(100);
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice); // getQuantizedValue(100), getQuantizedValue(100);
        uint256 fee = getQuantizedValue(1);

        uint256 feeRecipientBalance = token.balanceOf(users.feeRecipient);

        {
            // Sanity check
            assertTrue(totalPendingAssets == amount, "Initial setup is incorrect");
            assertTrue(pendingAssets == amount, "Initial setup is incorrect");
            assertTrue(pendingShares == amount, "Initial setup is incorrect");
        }

        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);

        (uint256 pendingAssetsAfter, uint256 pendingSharesAfter) = depositVault.pendingRedeemRequest(users.alice); //0, 0
        uint256 totalPendingAssetsAfter = depositVault.totalPendingAssets(); // 0

        uint256 tokenBalanceAfter = token.balanceOf(users.alice);

        assertEq(totalPendingAssetsAfter, totalPendingAssets - pendingAssets);
        assertEq(pendingAssetsAfter, 0);
        assertEq(pendingSharesAfter, 0);
        // assertEq(tokenBalanceAfter, tokenBalanceBefore + amount);
        assertEq(tokenBalanceBefore + amount - fee, tokenBalanceAfter);

        // verify that fee recipient received the funds
        assertEq(feeRecipientBalance + fee, token.balanceOf(users.feeRecipient));
    }

    function testFulfillRedeem__revertsOnZeroShares() public {
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets);
    }

    function testFulfillRedeem__revertsOnInvalidAmounts() public {
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares + 1, pendingAssets);

        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidAssetsAmount.selector));
        depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets + 1);
    }

    function testFulfillRedeem__revertsOnInsufficientAssets() public {
        moveAssetsFromVault(amount);
        vm.roll(block.number + 1);
        updateUnderlyingBalance(amount);

        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);

        try depositVault.fulfillRedeem(users.alice, pendingShares, pendingAssets) {
        fail();
        } catch Error(string memory reason) {
            assertTrue(_endsWith(reason, "transfer amount exceeds balance"), reason);
        } catch (bytes memory lowLevelData) {
            if (lowLevelData.length == 0) {
                return;             // for wbtc (ETHEREUM MAINNET)
            }

            if (lowLevelData.length >= 4) {
                bytes4 selector;
                assembly { selector := mload(add(lowLevelData, 32)) }
                if (selector == IERC20Errors.ERC20InsufficientBalance.selector) {
                    return; 
                }
            }

            fail(); // anything else fails
        }
    }

    function _endsWith(string memory str, string memory suffix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);
        if (suffixBytes.length > strBytes.length) return false;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[strBytes.length - suffixBytes.length + i] != suffixBytes[i]) return false;
        }
        return true;
    }

}
