// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/libraries/Errors.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestDeposit is BaseTest {
    using Math for uint256;

    function setUp() public override {
        BaseTest.setUp();
    }

    function test__deposit__Reverts__WithSharesLessThanMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(10);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 amount = 5 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__DepositAmountLessThanThreshold.selector, amount, minDepositAmount)
        );
        depositVault.deposit(amount, users.alice);

        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == aliceBalanceAfter, "Alice balance before and after is same");
    }

    function test__deposit__Success__WithAmountEqualToMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(100);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 amount = 100 * getQuantizedValue(1);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), amount)));
        depositVault.mint(amount, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == amount, "Alice balance after is not the amount");
    }

    function testDepositSuccess() public {
        uint256 amount = 100 * getQuantizedValue(1);
        uint256 aliceInitialBalance = getQuantizedValue(1_000_000);
        
        uint256 alicexTokensBalanceBefore = depositVault.balanceOf(users.alice);
        uint256 aliceTokensBalanceBefore = token.balanceOf(users.alice);
        assertTrue(alicexTokensBalanceBefore == 0, "Alice xTokens balance before is not 0");
        assertTrue(aliceTokensBalanceBefore == aliceInitialBalance, "Alice tokens balance does not match");

        vm.startPrank({msgSender: users.alice});
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), amount)));
        depositVault.deposit(amount, users.alice);

        uint256 alicexTokensBalanceAfter = depositVault.balanceOf(users.alice);
        uint256 aliceTokensBalanceAfter = token.balanceOf(users.alice);
        assertTrue(alicexTokensBalanceAfter == amount, "Alice xTokens balance after is not the amount");

        assertTrue(
            aliceTokensBalanceAfter == aliceInitialBalance - amount,
            "Alice token balance does not match after operation"
        );
    }

    function test_deposit_NoDoubleChargeUser() public {
        // initial deposit
        vm.startPrank(users.admin);
        deal(address(token), users.admin, getQuantizedValue(100));
        token.approve(address(depositVault), getQuantizedValue(100));
        depositVault.deposit(getQuantizedValue(100), users.admin);


        // Change deposit fee to 1%
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e16}), // setting fee to 1%
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        // sanity checks 
        assertEq(depositVault.totalSupply(), getQuantizedValue(100));
        assertEq(depositVault.totalAssets(), getQuantizedValue(100));


        // store the balances prior to deposit action
        uint256 aliceAssetBalanceBefore = token.balanceOf(users.alice); 
        uint256 aliceShareBalanceBefore = depositVault.balanceOf(users.alice); 
        uint256 feeRecipientAssetBalanceBefore = token.balanceOf(depositVault.getFeeRecipient());

        vm.startPrank(users.alice);

        uint256 assetsToDeposit = getQuantizedValue(100); // 100 tokens
        uint256 expectedShares = depositVault.previewDeposit(assetsToDeposit); // 99_009_900 shares (fee here is 990_100 tokens)
        uint256 expectedFee = Math.ceilDiv(assetsToDeposit * 1e16, 1e18 + 1e16);
        
        // sanity check
        assertEq(expectedShares, assetsToDeposit - expectedFee, "expected share mismatch");

        // approval was already set in Base.setup()
        depositVault.deposit(assetsToDeposit, users.alice);
        vm.stopPrank();

        // Verify alice's token balance has only decreased by getQuantizedValue(100);
        assertEq(token.balanceOf(users.alice), aliceAssetBalanceBefore - assetsToDeposit, "expected assets mismatch");

        // verify alice has received the expected amount of shares
        assertEq(depositVault.balanceOf(users.alice), aliceShareBalanceBefore + expectedShares, "expected shares mismatch");

        // verify fee recipient has received the expected fee
        assertEq(
            token.balanceOf(depositVault.getFeeRecipient()),
            feeRecipientAssetBalanceBefore + expectedFee,
            "fee recipient balance mismatch"    
        );

    }

    function test_deposit_NoDoubleChargeUser(uint256 randomYield) public {
        randomYield = bound(randomYield, 0, 1e25);

        // initial deposit
        vm.startPrank(users.admin);
        deal(address(token), users.admin, getQuantizedValue(100));
        token.approve(address(depositVault), getQuantizedValue(100));
        depositVault.deposit(getQuantizedValue(100), users.admin);


        // Change deposit fee to 1%
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e16}), // setting fee to 1%
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        // sanity checks 
        assertEq(depositVault.totalSupply(), getQuantizedValue(100));
        assertEq(depositVault.totalAssets(), getQuantizedValue(100));

        updateUnderlyingBalance(randomYield);


        // store the balances prior to deposit action
        uint256 aliceAssetBalanceBefore = token.balanceOf(users.alice); 
        uint256 aliceShareBalanceBefore = depositVault.balanceOf(users.alice); 
        uint256 feeRecipientAssetBalanceBefore = token.balanceOf(depositVault.getFeeRecipient());

        vm.startPrank(users.alice);

        uint256 assetsToDeposit = getQuantizedValue(100); // 100 tokens
        uint256 expectedShares = depositVault.previewDeposit(assetsToDeposit); 
        uint256 expectedFee = Math.mulDiv(assetsToDeposit, 1e16, (1e16 + 1e18), Math.Rounding.Ceil); 

        // approval was already set in Base.setup()
        depositVault.deposit(assetsToDeposit, users.alice);
        vm.stopPrank();

        // Verify alice's token balance has only decreased by getQuantizedValue(100);
        assertEq(token.balanceOf(users.alice), aliceAssetBalanceBefore - assetsToDeposit, "expected assets mismatch");

        // verify alice has received the expected amount of shares
        assertEq(depositVault.balanceOf(users.alice), aliceShareBalanceBefore + expectedShares, "expected shares mismatch");

        // verify fee recipient has received the expected fee
        assertEq(
            token.balanceOf(depositVault.getFeeRecipient()),
            feeRecipientAssetBalanceBefore + expectedFee,
            "fee recipient balance mismatch"    
        );

    }


}
