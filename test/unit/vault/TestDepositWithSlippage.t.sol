// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/libraries/Errors.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestDepositWithSlippage is BaseTest {
    using Math for uint256;

    function setUp() public override {
        BaseTest.setUp();

        // mimic the initial deposit by admin
        vm.startPrank(users.admin);
        deal(address(usdc), users.admin, 100e6);
        usdc.approve(address(depositVault), 100e6);
        depositVault.deposit(100e6, users.admin);
        vm.stopPrank();
    }

    // ================================ BASIC FUNCTIONALITY TESTS ================================

    function test__depositWithSlippage__Success__MinSharesEqualToActualShares() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares; // Exact match

        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        uint256 aliceAssetBalanceBefore = usdc.balanceOf(users.alice);
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(users.feeRecipient);

        vm.startPrank(users.alice);
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), assets)));
        
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        // Verify return value
        assertEq(actualShares, expectedShares, "Returned shares should match expected");
        
        // Verify state changes
        assertEq(depositVault.balanceOf(users.alice), aliceBalanceBefore + expectedShares, "Alice should receive expected shares");

        // Verify asset state changes
        assertEq(usdc.balanceOf(users.alice), aliceAssetBalanceBefore - assets, "Alice's asset should reduce");
        
        // Verify fee recipient received correct fee (deposit fee is 0, so should be same)
        assertEq(usdc.balanceOf(users.feeRecipient), feeRecipientBalanceBefore, "Fee recipient should not receive deposit fee");
    }

    function test__depositWithSlippage__Success__MinSharesLessThanActualShares() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares - 1e6; // Accept 1 USDC worth less

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should receive full expected shares");
        assertGt(actualShares, minShares, "Actual shares should be greater than minimum");
    }

    function test__depositWithSlippage__Revert__ActualSharesLessThanMinShares() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares + 1e6; // Unrealistic expectation

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientSharesReceived.selector, expectedShares, minShares)
        );
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();
    }

    function test__depositWithSlippage__Success__MeetsMinimumDepositThreshold() public {
        // Set minimum deposit amount
        vm.startPrank(users.admin);
        uint256 minDepositAmount = 50e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 assets = 100e6; // Above threshold
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares;

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should succeed when above minimum deposit threshold");
    }

    function test__depositWithSlippage__Revert__BelowMinimumDepositThreshold() public {
        // Set minimum deposit amount
        vm.startPrank(users.admin);
        uint256 minDepositAmount = 100e6;
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 assets = 50e6; // Below threshold
        uint256 minShares = 1; // Any value

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.DepositAmountLessThanThreshold.selector, assets, minDepositAmount)
        );
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();
    }

    // ================================ EDGE CASES ================================

    function test__depositWithSlippage__Success__MinimalSlippageProtection() public {
        uint256 assets = 100e6;
        uint256 minShares = 1; // Minimal protection

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertGt(actualShares, minShares, "Should receive much more than minimal protection");
    }

    function test__depositWithSlippage__Revert__UnrealisticMinShares() public {
        uint256 assets = 100e6;
        uint256 minShares = 1000e6; // Expecting 10x more shares than assets

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientSharesReceived.selector, assets, minShares)
        );
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();
    }

    function test__depositWithSlippage__Success__ZeroMinShares() public {
        uint256 assets = 100e6;
        uint256 minShares = 0; // No slippage protection

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertGt(actualShares, 0, "Should receive shares even with no slippage protection");
    }

    // ================================ EXCHANGE RATE SCENARIOS ================================

    function test__depositWithSlippage__Success__OneToOneExchangeRate() public {
        uint256 assets = 100e6;
        uint256 expectedShares = 100e6; // 1:1 ratio initially
        uint256 minShares = expectedShares;

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should maintain 1:1 exchange rate initially");
    }

    function test__depositWithSlippage__Revert__UnfavorableExchangeRate() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares; // Expecting at least 100 shares for 100 assets 

        updateUnderlyingBalance(100e6); // Add underlying balance
        // 1 share price is not 2 USDC
        // with 100 assets, you will only get 50 shares

        vm.startPrank(users.bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientSharesReceived.selector, 50e6, minShares)
        );
        uint256 actualShares = depositVault.deposit(assets, users.bob, minShares);
        vm.stopPrank();
    }

    function test__depositWithSlippage__Success__FavorableExchangeRate() public {
        // Simulate favourable rate by moving assets out (loss scenario)
        moveAssetsFromVault(50e6);

        // totalSupply = 100
        // totalAssets = 50
        // 1 share = 0.5 USDC

        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = 150e6; 

        vm.startPrank(users.bob);
        uint256 actualShares = depositVault.deposit(assets, users.bob, minShares);
        vm.stopPrank();

        assertGt(actualShares, minShares, "Should receive more shares due to favorable exchange rate");
        assertEq(actualShares, expectedShares, "Should match preview calculation");
    }

    // ================================ DIFFERENT RECEIVERS ================================

    function test__depositWithSlippage__Success__DifferentReceiver() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares;

        uint256 bobBalanceBefore = depositVault.balanceOf(users.bob);

        vm.startPrank(users.alice);
        // Alice pays, Bob receives
        uint256 actualShares = depositVault.deposit(assets, users.bob, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should return correct shares");
        assertEq(depositVault.balanceOf(users.bob), bobBalanceBefore + expectedShares, "Bob should receive the shares");
        assertEq(depositVault.balanceOf(users.alice), 0, "Alice should not receive shares");
    }

    function test__depositWithSlippage__Success__ReceiverIsContract() public {
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares;

        address contractReceiver = address(depositVault); // Use vault as receiver

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, contractReceiver, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should work with contract receiver");
        assertEq(depositVault.balanceOf(contractReceiver), expectedShares, "Contract should receive shares");
    }

    // ================================ STATE VERIFICATION TESTS ================================

    function test__depositWithSlippage__Verify__CorrectUSDCTransfer() public {
        uint256 assets = 100e6;
        uint256 minShares = 90e6;

        uint256 aliceUSDCBefore = usdc.balanceOf(users.alice);
        uint256 vaultUSDCBefore = usdc.balanceOf(address(depositVault));

        vm.startPrank(users.alice);
        vm.expectCall(address(usdc), abi.encodeCall(usdc.transferFrom, (users.alice, address(depositVault), assets)));
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(usdc.balanceOf(users.alice), aliceUSDCBefore - assets, "Alice USDC should decrease by assets");
        assertEq(usdc.balanceOf(address(depositVault)), vaultUSDCBefore + assets, "Vault USDC should increase by assets");
    }

    function test__depositWithSlippage__Verify__TotalAssetsAndSupplyUpdate() public {
        uint256 assets = 100e6;
        uint256 minShares = 90e6;

        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 totalSupplyBefore = depositVault.totalSupply();

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(depositVault.totalAssets(), totalAssetsBefore + assets, "Total assets should increase by deposited amount");
        assertEq(depositVault.totalSupply(), totalSupplyBefore + actualShares, "Total supply should increase by minted shares");
    }

    function test__depositWithSlippage__Verify__FeeRecipientReceivesCorrectFee() public {
        // Update fee to non-zero for this test
        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 2e6}), // 2 USDC fee
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        uint256 assets = 100e6;
        uint256 expectedFee = 2e6; // 2 USDC flat fee
        uint256 expectedShares = depositVault.previewDeposit(assets); // This should account for fee
        uint256 minShares = expectedShares;

        uint256 feeRecipientBalanceBefore = usdc.balanceOf(users.feeRecipient);

        vm.startPrank(users.alice);
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(
            usdc.balanceOf(users.feeRecipient), 
            feeRecipientBalanceBefore + expectedFee, 
            "Fee recipient should receive correct deposit fee"
        );
    }

    // ================================ FUZZING TESTS ================================

    function testFuzz__depositWithSlippage__Success(uint256 assets, uint256 slippageBps) public {
        // Bound inputs to reasonable ranges
        assets = bound(assets, 1e6, 1000000e6); // 1 USDC to 1M USDC
        slippageBps = bound(slippageBps, 0, 1000); // 0% to 10% slippage tolerance

        // Ensure Alice has enough USDC
        deal(address(usdc), users.alice, assets * 2);
        vm.startPrank(users.alice);
        usdc.approve(address(depositVault), assets);
        vm.stopPrank();

        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares.mulDiv(10000 - slippageBps, 10000, Math.Rounding.Floor);

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertGe(actualShares, minShares, "Should receive at least minimum shares");
        assertEq(actualShares, expectedShares, "Should match preview calculation");
    }

    function testFuzz__depositWithSlippage__Revert__UnreasonableMinShares(uint256 assets, uint256 minShares) public {
        // Bound inputs
        assets = bound(assets, 1e6, 1000000e6);
        
        uint256 expectedShares = depositVault.previewDeposit(assets);
        minShares = bound(minShares, expectedShares + 1, type(uint256).max / 2); // Always higher than possible

        // Ensure Alice has enough USDC
        deal(address(usdc), users.alice, assets * 2);
        vm.startPrank(users.alice);
        usdc.approve(address(depositVault), assets);
        vm.stopPrank();

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientSharesReceived.selector, expectedShares, minShares)
        );
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();
    }

    // ================================ INTEGRATION WITH PAUSED STATE ================================

    function test__depositWithSlippage__Revert__WhenPaused() public {
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        uint256 assets = 100e6;
        uint256 minShares = 90e6;

        vm.startPrank(users.alice);
        vm.expectRevert("EnforcedPause()");
        depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();
    }

    // ================================ COMPLEX SCENARIO TESTS ================================

    function test__depositWithSlippage__Success__EdgeCaseWithMinimalAmounts() public {
        uint256 assets = 1; // 1 wei asset
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares > 0 ? expectedShares - 1 : 0; // Allow 1 wei slippage

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertEq(actualShares, expectedShares, "Should work with minimal amounts");
        assertEq(depositVault.balanceOf(users.alice), actualShares, "Should receive calculated shares");
    }

    function test__depositWithSlippage__Success__LargeAmountsWithTightSlippage() public {
        uint256 assets = 1000000e6; // 1M USDC
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares.mulDiv(9999, 10000, Math.Rounding.Floor); // 0.01% slippage tolerance

        // Ensure Alice has enough USDC
        deal(address(usdc), users.alice, assets * 2);
        vm.startPrank(users.alice);
        usdc.approve(address(depositVault), assets);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 actualShares = depositVault.deposit(assets, users.alice, minShares);
        vm.stopPrank();

        assertGe(actualShares, minShares, "Should meet tight slippage tolerance");
        assertEq(actualShares, expectedShares, "Should receive expected shares for large amount");
    }

    function test__depositWithSlippage__Integration__WithExistingVaultState() public {
        // Setup complex vault state with multiple operations
        vm.startPrank(users.alice);
        depositVault.deposit(500e6, users.alice);
        vm.stopPrank();

        // Simulate some external activity (funds moved to strategies)
        moveAssetsFromVault(200e6);
        updateUnderlyingBalance(300e6);
        vm.roll(block.number+1);


        // Add back some profit from strategies
        updateUnderlyingBalance(350e6);
        unpauseVault();

        // Now Bob deposits into this complex state
        uint256 assets = 100e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares.mulDiv(95, 100, Math.Rounding.Floor); // 5% slippage tolerance

        vm.startPrank(users.bob);
        uint256 actualShares = depositVault.deposit(assets, users.bob, minShares);
        vm.stopPrank();

        assertGe(actualShares, minShares, "Should respect slippage protection");
        assertEq(actualShares, expectedShares, "Should receive calculated shares based on current vault state");
        assertEq(depositVault.balanceOf(users.bob), actualShares, "Bob should receive the shares");
    }

    function test__depositWithSlippage__Success__SequentialDepositsWithChangingRates() public {
        // user deposits
        vm.startPrank(users.alice);
        uint256 aliceAssets = 100e6;
        uint256 aliceExpectedShares = depositVault.previewDeposit(aliceAssets);
        uint256 aliceActualShares = depositVault.deposit(aliceAssets, users.alice, aliceExpectedShares);
        vm.stopPrank();

        assertEq(aliceActualShares, aliceExpectedShares, "Alice should get expected shares");

        // Vault generates some yield
        updateUnderlyingBalance(20e6);

        // Second user deposits at new rate
        vm.startPrank(users.bob);
        uint256 bobAssets = 60e6;
        uint256 bobExpectedShares = depositVault.previewDeposit(bobAssets);
        uint256 bobMinShares = bobExpectedShares.mulDiv(98, 100, Math.Rounding.Floor); // 2% slippage
        uint256 bobActualShares = depositVault.deposit(bobAssets, users.bob, bobMinShares);
        vm.stopPrank();

        assertGe(bobActualShares, bobMinShares, "Bob should meet slippage protection");
        assertLt(bobActualShares, bobAssets, "Bob should get fewer shares due to increased share value");

        // Verify total state consistency
        uint256 totalAssets = depositVault.totalAssets();
        uint256 totalSupply = depositVault.totalSupply();
        assertEq(totalAssets, 100e6 + 100e6 + 20e6 + 60e6, "Total assets should equal deposits plus yield"); // 100 admin deposit + 100 alice deposit + 20 yield + 60 bob deposit
        assertEq(totalSupply, 100e6 + aliceActualShares + bobActualShares, "Total supply should equal sum of shares"); // 100 is the first deposit by admin
    }

    function test__depositWithSlippage__Success__DepositAfterPartialWithdrawals() public {
        // Setup initial state with deposits
        vm.startPrank(users.alice);
        depositVault.deposit(200e6, users.alice);
        vm.stopPrank();

        vm.startPrank(users.bob);
        depositVault.deposit(200e6, users.bob);
        vm.stopPrank();

        // Simulate partial withdrawals through redemption (simplified for test)
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 totalAssetsBefore = depositVault.totalAssets();

        // Simulate some shares being redeemed (burn shares, move assets)
        moveAssetsFromVault(100e6);
        updateUnderlyingBalance(300e6); // Reduce underlying balance

        // Now a new user deposits into this post-withdrawal state
        uint256 assets = 150e6;
        uint256 expectedShares = depositVault.previewDeposit(assets);
        uint256 minShares = expectedShares.mulDiv(97, 100, Math.Rounding.Floor); // 3% slippage

        // Create new user for this test
        (address charlie, ) = createUser("Charlie");

        vm.startPrank(charlie);
        uint256 actualShares = depositVault.deposit(assets, charlie, minShares);
        vm.stopPrank();

        assertGe(actualShares, minShares, "Should meet slippage protection");
        assertEq(actualShares, expectedShares, "Should receive calculated shares");
        assertEq(depositVault.balanceOf(charlie), actualShares, "Charlie should receive the shares");
    }

    function test__depositWithSlippage__Success__DepositWithFeesAndComplexState() public {
        // Set up non-zero deposit fee for this test
        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // 0.1% fee
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();


        // Add yield and move some funds
        updateUnderlyingBalance(100e6);

        uint256 assets = 200e6;
        uint256 expectedShares = depositVault.previewDeposit(assets); // Should account for fee
        uint256 minShares = expectedShares.mulDiv(98, 100, Math.Rounding.Floor); // 2% slippage
        
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(users.feeRecipient);

        vm.startPrank(users.bob);
        uint256 actualShares = depositVault.deposit(assets, users.bob, minShares);
        vm.stopPrank();

        assertGe(actualShares, minShares, "Should meet slippage protection even with fees");
        assertEq(actualShares, expectedShares, "Should receive expected shares after fee deduction");
        
        // Verify fee was collected
        uint256 expectedFee = assets.mulDiv(1e15, 1e18 + 1e15, Math.Rounding.Ceil); // 0.1% of 200e6
        assertEq(
            usdc.balanceOf(users.feeRecipient), 
            feeRecipientBalanceBefore + expectedFee, 
            "Fee recipient should receive correct fee"
        );
    }
}