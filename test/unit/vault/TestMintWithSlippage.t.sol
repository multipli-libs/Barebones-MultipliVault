// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/libraries/Errors.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestMintWithSlippage is BaseTest {
    using Math for uint256;

    function setUp() public override {
        BaseTest.setUp();

        // mimic the initial deposit by admin
        vm.startPrank(users.admin);
        deal(address(token), users.admin, getQuantizedValue(100));
        token.approve(address(depositVault), getQuantizedValue(100));
        depositVault.deposit(getQuantizedValue(100), users.admin);
        vm.stopPrank();
    }

    // ================================ BASIC FUNCTIONALITY TESTS ================================

    function test__mintWithSlippage__Success__MaxAssetsEqualToActualAssets() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets; // Exact match

        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);
        uint256 aliceAssetBalanceBefore = token.balanceOf(users.alice);
        uint256 feeRecipientBalanceBefore = token.balanceOf(users.feeRecipient);

        vm.startPrank(users.alice);
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), expectedAssets)));
        
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        // Verify return value
        assertEq(actualAssets, expectedAssets, "Returned assets should match expected");
        
        // Verify share balance state changes for Alice
        assertEq(depositVault.balanceOf(users.alice), aliceBalanceBefore + shares, "Alice should receive exact shares requested");

        // Verify asset balance state changes for Alice
        assertEq(token.balanceOf(users.alice), aliceAssetBalanceBefore - expectedAssets, "Alice should have the exact asset deducted");
        
        // Verify fee recipient received correct fee (deposit fee is 0, so should be same)
        assertEq(token.balanceOf(users.feeRecipient), feeRecipientBalanceBefore, "Fee recipient should not receive deposit fee");
    }

    function test__mintWithSlippage__Success__MaxAssetsGreaterThanActualAssets() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets + getQuantizedValue(10); // Allow extra 10 tokens

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should only use expected assets");
        assertLt(actualAssets, maxAssets, "Actual assets should be less than maximum");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive exact shares requested");
    }

    function test__mintWithSlippage__Revert__ActualAssetsGreaterThanMaxAssets() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets - getQuantizedValue(1); // Unrealistic limit

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, expectedAssets, maxAssets)
        );
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    function test__mintWithSlippage__Revert__IncreaseSharesBetweenPreviewAndMint() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares); // 100
        uint256 maxAssets = expectedAssets; // 100

        uint256 increasedShares = shares + 1;
        uint256 expectedIncreasedAssets = depositVault.previewMint(increasedShares);

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, expectedIncreasedAssets, maxAssets)
        );
        depositVault.mint(increasedShares, users.alice, maxAssets); // use increased shares
        vm.stopPrank();
    }

    function test__mintWithSlippage__Success__MeetsMinimumDepositThreshold() public {
        // Set minimum deposit amount
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(50);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares); // Should be getQuantizedValue(100), above threshold
        uint256 maxAssets = expectedAssets;

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should succeed when above minimum deposit threshold");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive requested shares");
    }

    function test__mintWithSlippage__Revert__BelowMinimumDepositThreshold() public {
        // Set minimum deposit amount
        vm.startPrank(users.admin);
        uint256 minDepositAmount = getQuantizedValue(100);
        depositVault.updateMinDepositAmount(minDepositAmount);
        vm.stopPrank();

        uint256 shares = getQuantizedValue(50); // This will require ~getQuantizedValue(50); assets, below threshold
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets;

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__DepositAmountLessThanThreshold.selector, expectedAssets, minDepositAmount)
        );
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    // ================================ EDGE CASES ================================

    function test__mintWithSlippage__Revert__ZeroMaxAssets() public {
        uint256 shares = getQuantizedValue(100);
        uint256 maxAssets = 0; // No assets allowed

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, shares, maxAssets) // Will require getQuantizedValue(100); assets
        );
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    function test__mintWithSlippage__Success__MaximalSlippageTolerance() public {
        uint256 shares = getQuantizedValue(100);
        uint256 maxAssets = type(uint256).max; // No limit

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, shares, "Should use expected assets (1:1 ratio initially)");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive requested shares");
    }

    function test__mintWithSlippage__Success__OneWeiDifference() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets + 1; // Allow 1 wei extra

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should work with minimal slippage tolerance");
    }

    function test__mintWithSlippage__Revert__UnrealisticMaxAssets() public {
        uint256 shares = getQuantizedValue(100);
        uint256 maxAssets = getQuantizedValue(10); // Expecting to pay only 10 tokens for 100 shares

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, shares, maxAssets)
        );
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    // ================================ EXCHANGE RATE SCENARIOS ================================

    function test__mintWithSlippage__Success__OneToOneExchangeRate() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = getQuantizedValue(100); // 1:1 ratio initially
        uint256 maxAssets = expectedAssets;

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should maintain 1:1 exchange rate initially");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive exact shares requested");
    }

    function test__mintWithSlippage__Revert__UnfavorableExchangeRate() public {
        // Add profits to vault (simulate yield generation)
        updateUnderlyingBalance(getQuantizedValue(200)); // Add underlying balance (1 share = 3 tokens)

        uint256 shares = getQuantizedValue(50);
        uint256 expectedAssets = depositVault.previewMint(shares); // 150
        uint256 maxAssets = getQuantizedValue(100); // Willing to pay up to 100 tokens for 50 shares

        vm.startPrank(users.bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, expectedAssets, maxAssets)
        );
        uint256 actualAssets = depositVault.mint(shares, users.bob, maxAssets);
        vm.stopPrank();
    }

    function test__mintWithSlippage__Success__FavorableExchangeRate() public {
        // Simulate unfavorable rate by moving assets out (loss scenario)
        moveAssetsFromVault(getQuantizedValue(50));
        // updateUnderlyingBalance(getQuantizedValue(50); // Update underlying to reflect loss

        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares); // 50
        uint256 maxAssets = getQuantizedValue(100); // Unrealistic limit given the loss

        vm.startPrank(users.bob);
        uint256 actualAssets = depositVault.mint(shares, users.bob, maxAssets);
        vm.stopPrank();


        assertLt(actualAssets, maxAssets, "Should require fewer assets due to favorable exchange rate");
        assertEq(actualAssets, expectedAssets, "Should match preview calculation");
        assertEq(depositVault.balanceOf(users.bob), shares, "Bob should receive exact shares requested");
    }

    // ================================ DIFFERENT RECEIVERS ================================

    function test__mintWithSlippage__Success__DifferentReceiver() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets;

        uint256 bobBalanceBefore = depositVault.balanceOf(users.bob);
        uint256 aliceBalanceBefore = depositVault.balanceOf(users.alice);

        vm.startPrank(users.alice);
        // Alice pays, Bob receives
        uint256 actualAssets = depositVault.mint(shares, users.bob, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should return correct assets");
        assertEq(depositVault.balanceOf(users.bob), bobBalanceBefore + shares, "Bob should receive the shares");
        assertEq(depositVault.balanceOf(users.alice), aliceBalanceBefore, "Alice should not receive shares");
    }

    function test__mintWithSlippage__Success__ReceiverIsContract() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets;

        address contractReceiver = address(depositVault); // Use vault as receiver

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, contractReceiver, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should work with contract receiver");
        assertEq(depositVault.balanceOf(contractReceiver), shares, "Contract should receive shares");
    }

    // ================================ STATE VERIFICATION TESTS ================================

    function test__mintWithSlippage__Verify__CorrectTokenTransfer() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets;

        uint256 aliceTokensBefore = token.balanceOf(users.alice);
        uint256 vaultTokensBefore = token.balanceOf(address(depositVault));

        vm.startPrank(users.alice);
        vm.expectCall(address(token), abi.encodeCall(token.transferFrom, (users.alice, address(depositVault), expectedAssets)));
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(token.balanceOf(users.alice), aliceTokensBefore - expectedAssets, "Alice tokens should decrease by expected assets");
        assertEq(token.balanceOf(address(depositVault)), vaultTokensBefore + expectedAssets, "Vault tokens should increase by expected assets");
    }

    function test__mintWithSlippage__Verify__ExactSharesMinted() public {
        uint256 shares = getQuantizedValue(100);
        uint256 maxAssets = getQuantizedValue(150); // Allow some slippage

        uint256 aliceSharesBefore = depositVault.balanceOf(users.alice);

        vm.startPrank(users.alice);
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), aliceSharesBefore + shares, "Should mint exact shares requested");
    }

    function test__mintWithSlippage__Verify__TotalAssetsAndSupplyUpdate() public {
        uint256 shares = getQuantizedValue(100);
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets;

        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 totalSupplyBefore = depositVault.totalSupply();

        vm.startPrank(users.alice);
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(depositVault.totalAssets(), totalAssetsBefore + expectedAssets, "Total assets should increase by used assets");
        assertEq(depositVault.totalSupply(), totalSupplyBefore + shares, "Total supply should increase by minted shares");
    }

    function test__mintWithSlippage__Verify__FeeRecipientReceivesCorrectFee() public {
        // Update fee to non-zero for this test
        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(3)}), // 3 tokens fee
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        uint256 shares = getQuantizedValue(100);
        uint256 expectedFee = getQuantizedValue(3); // 3 tokens flat fee
        uint256 expectedAssets = depositVault.previewMint(shares); // This should account for fee
        uint256 maxAssets = expectedAssets;

        uint256 feeRecipientBalanceBefore = token.balanceOf(users.feeRecipient);

        vm.startPrank(users.alice);
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(
            token.balanceOf(users.feeRecipient), 
            feeRecipientBalanceBefore + expectedFee, 
            "Fee recipient should receive correct deposit fee"
        );
    }

    // ================================ FUZZING TESTS ================================

    function testFuzz__mintWithSlippage__Success(uint256 shares, uint256 slippageBps) public {
        // Bound inputs to reasonable ranges
        shares = bound(shares, getQuantizedValue(1), getQuantizedValue(1_000_000)); // 1 to 1M shares
        slippageBps = bound(slippageBps, 0, 1000); // 0% to 10% slippage tolerance

        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets.mulDiv(10000 + slippageBps, 10000, Math.Rounding.Ceil);

        // Ensure Alice has enough tokens
        deal(address(token), users.alice, maxAssets * 2);
        vm.startPrank(users.alice);
        token.approve(address(depositVault), maxAssets);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertLe(actualAssets, maxAssets, "Should not exceed maximum assets");
        assertEq(actualAssets, expectedAssets, "Should match preview calculation");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive exact shares requested");
    }

    function testFuzz__mintWithSlippage__Revert__UnreasonableMaxAssets(uint256 shares, uint256 maxAssets) public {
        // Bound inputs
        shares = bound(shares, getQuantizedValue(1), getQuantizedValue(1_000_000));
        
        uint256 expectedAssets = depositVault.previewMint(shares);
        maxAssets = bound(maxAssets, 0, expectedAssets - 1); // Always lower than required

        // Ensure Alice has enough tokens
        deal(address(token), users.alice, expectedAssets * 2);
        vm.startPrank(users.alice);
        token.approve(address(depositVault), expectedAssets);
        vm.stopPrank();

        vm.startPrank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__ExcessiveAssetsRequired.selector, expectedAssets, maxAssets)
        );
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    function testFuzz__mintWithSlippage__DifferentExchangeRates(uint256 initialDeposit, uint256 profit, uint256 shares) public {
        // Bound inputs
        initialDeposit = bound(initialDeposit, getQuantizedValue(100), getQuantizedValue(10000));
        profit = bound(profit, 0, initialDeposit); // Profit up to 100% of initial
        shares = bound(shares, getQuantizedValue(1), getQuantizedValue(1000));

        // Setup vault with some assets and profits
        vm.startPrank(users.alice);
        depositVault.deposit(initialDeposit, users.alice);
        vm.stopPrank();

        if (profit > 0) {
            updateUnderlyingBalance(profit);
        }

        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets.mulDiv(110, 100, Math.Rounding.Ceil); // 10% slippage tolerance

        // Ensure Bob has enough tokens
        deal(address(token), users.bob, maxAssets * 2);
        vm.startPrank(users.bob);
        token.approve(address(depositVault), maxAssets);
        vm.stopPrank();

        vm.startPrank(users.bob);
        uint256 actualAssets = depositVault.mint(shares, users.bob, maxAssets);
        vm.stopPrank();

        assertLe(actualAssets, maxAssets, "Should not exceed maximum assets");
        assertEq(depositVault.balanceOf(users.bob), shares, "Should receive exact shares requested");
    }

    // ================================ INTEGRATION WITH PAUSED STATE ================================

    function test__mintWithSlippage__Revert__WhenPaused() public {
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        uint256 shares = getQuantizedValue(100);
        uint256 maxAssets = getQuantizedValue(150);

        vm.startPrank(users.alice);
        vm.expectRevert("EnforcedPause()");
        depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();
    }

    // ================================ COMPLEX SCENARIO TESTS ================================


    function test__mintWithSlippage__Success__EdgeCaseWithMinimalAmounts() public {
        uint256 shares = 1; // 1 wei share
        uint256 expectedAssets = depositVault.previewMint(shares);
        uint256 maxAssets = expectedAssets + 1; // Allow 1 wei slippage

        vm.startPrank(users.alice);
        uint256 actualAssets = depositVault.mint(shares, users.alice, maxAssets);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets, "Should work with minimal amounts");
        assertEq(depositVault.balanceOf(users.alice), shares, "Should receive 1 wei share");
    }
}