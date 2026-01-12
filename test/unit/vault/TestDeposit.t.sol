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
        uint256 minDepositAmount = 10e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 amount = 5 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.DepositAmountLessThanThreshold.selector, amount, minDepositAmount)
        );
        depositVault.deposit(amount, users.alice);

        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == aliceBalanceAfter, "Alice balance before and after is same");
    }

    function test__deposit__Success__WithAmountEqualToMinimumDepositAmount() public {
        vm.startPrank(users.admin);
        uint256 minDepositAmount = 100e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 amount = 100 * 1e6;
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceBefore == 0, "Alice balance before is not 0");

        vm.startPrank(users.alice);
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), amount)));
        depositVault.mint(amount, users.alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = depositVault.balanceOf(users.alice);
        assertTrue(aliceBalanceAfter == amount, "Alice balance after is not the amount");
    }

    function testDepositSuccess() public {
        uint256 amount = 100 * 1e6;
        uint256 alicexUSDCBalanceBefore = depositVault.balanceOf(users.alice);
        uint256 aliceUSDCBalanceBefore = usdc.balanceOf(users.alice);
        assertTrue(alicexUSDCBalanceBefore == 0, "Alice xUSDC balance before is not 0");
        assertTrue(aliceUSDCBalanceBefore == 1_000_000e6, "Alice USDC balance does not match");

        vm.startPrank({msgSender: users.alice});
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), amount)));
        depositVault.deposit(amount, users.alice);

        uint256 alicexUSDCBalanceAfter = depositVault.balanceOf(users.alice);
        uint256 aliceUSDCBalanceAfter = usdc.balanceOf(users.alice);
        assertTrue(alicexUSDCBalanceAfter == amount, "Alice xUSDC balance after is not the amount");
        assertTrue(aliceUSDCBalanceAfter == 1_000_000e6 - amount, "Alice USDC balance does not match after operation");
    }

    function test_deposit_NoDoubleChargeUser() public {
        // initial deposit
        vm.startPrank(users.admin);
        deal(address(usdc), users.admin, 100e6);
        usdc.approve(address(depositVault), 100e6);
        depositVault.deposit(100e6, users.admin);


        // Change deposit fee to 1%
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e16}), // setting fee to 1%
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        // sanity checks 
        assertEq(depositVault.totalSupply(), 100e6);
        assertEq(depositVault.totalAssets(), 100e6);


        // store the balances prior to deposit action
        uint256 aliceAssetBalanceBefore = usdc.balanceOf(users.alice); 
        uint256 aliceShareBalanceBefore = depositVault.balanceOf(users.alice); 
        uint256 feeRecipientAssetBalanceBefore = usdc.balanceOf(depositVault.getFeeRecipient());

        vm.startPrank(users.alice);

        uint256 assetsToDeposit = 100e6; // 100 USDC
        uint256 expectedShares = depositVault.previewDeposit(assetsToDeposit); // 99_009_900 shares (fee here is 990_100 USDC)
        uint256 expectedFee = 990_100; // assets.mulDiv(1e16, (1e18 + 1e16)); round it up
        
        // sanity check
        assertEq(expectedShares, 99_009_900, "expected share mismatch");

        // approval was already set in Base.setup()
        depositVault.deposit(assetsToDeposit, users.alice);
        vm.stopPrank();

        // Verify alice's usdc balance has only decreased by 100e6
        assertEq(usdc.balanceOf(users.alice), aliceAssetBalanceBefore - assetsToDeposit, "expected assets mismatch");

        // verify alice has received the expected amount of shares
        assertEq(depositVault.balanceOf(users.alice), aliceShareBalanceBefore + expectedShares, "expected shares mismatch");

        // verify fee recipient has received the expected fee
        assertEq(
            usdc.balanceOf(depositVault.getFeeRecipient()),
            feeRecipientAssetBalanceBefore + expectedFee,
            "fee recipient balance mismatch"    
        );

    }

    function test_deposit_NoDoubleChargeUser(uint256 randomYield) public {
        randomYield = bound(randomYield, 0, 1e25);

        // initial deposit
        vm.startPrank(users.admin);
        deal(address(usdc), users.admin, 100e6);
        usdc.approve(address(depositVault), 100e6);
        depositVault.deposit(100e6, users.admin);


        // Change deposit fee to 1%
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e16}), // setting fee to 1%
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        // sanity checks 
        assertEq(depositVault.totalSupply(), 100e6);
        assertEq(depositVault.totalAssets(), 100e6);

        updateUnderlyingBalance(randomYield);


        // store the balances prior to deposit action
        uint256 aliceAssetBalanceBefore = usdc.balanceOf(users.alice); 
        uint256 aliceShareBalanceBefore = depositVault.balanceOf(users.alice); 
        uint256 feeRecipientAssetBalanceBefore = usdc.balanceOf(depositVault.getFeeRecipient());

        vm.startPrank(users.alice);

        uint256 assetsToDeposit = 100e6; // 100 USDC
        uint256 expectedShares = depositVault.previewDeposit(assetsToDeposit); 
        uint256 expectedFee = Math.mulDiv(assetsToDeposit, 1e16, (1e16 + 1e18), Math.Rounding.Ceil); 

        // approval was already set in Base.setup()
        depositVault.deposit(assetsToDeposit, users.alice);
        vm.stopPrank();

        // Verify alice's usdc balance has only decreased by 100e6
        assertEq(usdc.balanceOf(users.alice), aliceAssetBalanceBefore - assetsToDeposit, "expected assets mismatch");

        // verify alice has received the expected amount of shares
        assertEq(depositVault.balanceOf(users.alice), aliceShareBalanceBefore + expectedShares, "expected shares mismatch");

        // verify fee recipient has received the expected fee
        assertEq(
            usdc.balanceOf(depositVault.getFeeRecipient()),
            feeRecipientAssetBalanceBefore + expectedFee,
            "fee recipient balance mismatch"    
        );

    }


}
