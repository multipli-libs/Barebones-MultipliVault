// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "../../../src/managers/VaultFundManager.sol";
import {Errors} from "../../../src/libraries/Errors.sol";
import {IMultipliVault} from "../../../src/interfaces/IMultipliVault.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {MultipliVault} from "../../../src/vault/MultipliVault.sol";

contract TestAddFundsAndFulfillRedeem is VaultFundManagerBase {
    event FundsAddedAndRedemptionFulfilled(
        address indexed receiver, uint256 shares, uint256 assetsWithFee, uint256 newAggregatedBalance
    );

    function setUp() public override {
        super.setUp();

        // Deposit funds into vault for Alice
        depositForUser(users.alice, INITIAL_DEPOSIT);
        depositForUser(users.bob, INITIAL_DEPOSIT - getQuantizedValue(50_000)); //50,000

        // First, remove some funds from vault to create aggregated balance
        // This simulates funds being moved to exchanges
        bytes memory data =
            abi.encodeWithSelector(fundManager.removeFundsFromVault.selector, recipient1, TEST_TRANSFER_AMOUNT);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);
        vm.stopPrank();

        vm.roll(block.number + 1);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWhenNotCalledByVault() public {
        uint256 shares = 1000e18;
        uint256 assetsWithFee = vault.previewRedeem(shares);

        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.addFundsAndFulfillRedeem(users.alice, shares, assetsWithFee);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithZeroReceiver() public {
        uint256 shares = 1000e18;
        uint256 assetsWithFee = vault.previewRedeem(shares);

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, address(0), shares, assetsWithFee);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.VaultFundManager__ZeroAddress.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithZeroShares() public {
        uint256 assetsWithFee = getQuantizedValue(1000);

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, 0, assetsWithFee);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.VaultFundManager__ZeroAmount.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithZeroAssetsWithFee() public {
        uint256 shares = 1000e18;

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, 0);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.VaultFundManager__ZeroAmount.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithInsufficientContractBalanceInVaultFundManager() public {
        uint256 contractBalance = token.balanceOf(address(fundManager));
        uint256 excessiveAmount = contractBalance + 1;
        uint256 shares = 1000e18;

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, excessiveAmount);

        vm.startPrank(users.alice);
        vm.expectRevert(VaultFundManager.VaultFundManager__InsufficientBalance.selector);
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithoutValidRedemptionRequest() public {
        uint256 shares = getQuantizedValue(1000);
        uint256 assetsWithOutFee = vault.previewRedeem(shares);

        // Don't create a redemption request first
        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.bob, shares, assetsWithOutFee);

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_Success() public {
        uint256 amountOfAssets = getQuantizedValue(50_000);

        assertEq(vault.balanceOf(users.bob), amountOfAssets, "bob should own `amountOfAssets` shares");

        uint256 shares = getQuantizedValue(10_000); // Redeem 10,000 shares
        uint256 assetsWithOutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        // Create redemption request
        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.RedeemRequest(users.bob, users.bob, assetsWithFee, shares);
        createRedemptionRequest(users.bob, shares);

        // progress the block
        vm.roll(block.number + 1);

        uint256 initialUserBalance = token.balanceOf(users.bob);
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialFundManagerBalance = token.balanceOf(address(fundManager));
        uint256 initialAggregatedBalance = vault.aggregatedUnderlyingBalances();
        uint256 initialTotalSupply = vault.totalSupply();

        // Get pending redeem info
        (uint256 pendingAssets, uint256 pendingShares) = vault.pendingRedeemRequest(users.bob);
        assertEq(pendingShares, shares, "pending shares should be equal to `shares`");
        assertEq(pendingAssets, assetsWithFee, "assetsWithFee should be equal to `assetsWithFee`");

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.bob, shares, assetsWithFee);

        vm.startPrank(users.alice); // Alice is fund manager
        vault.manage(address(fundManager), data, 0);

        // Check user received the assets
        assertEq(token.balanceOf(users.bob), initialUserBalance + assetsWithFee - getQuantizedValue(1), "bob's balance mismatch"); // Minus withdrawal fee

        // Check vault balance increased
        assertEq(token.balanceOf(address(vault)), initialVaultBalance, "vault's balance mismatch");

        // Check fund manager balance decreased
        assertEq(
            token.balanceOf(address(fundManager)),
            initialFundManagerBalance - assetsWithFee,
            "fund manager's balance mismatch"
        );

        // Check aggregated balance decreased
        assertEq(
            vault.aggregatedUnderlyingBalances(),
            initialAggregatedBalance - assetsWithFee,
            "aggregated balance should decrease"
        );

        // Check total supply decreased (shares burned)
        assertEq(vault.totalSupply(), initialTotalSupply - shares, "total supply should reduce by share amount");

        // Check pending redemption is cleared
        (uint256 finalPendingAssets, uint256 finalPendingShares) = vault.pendingRedeemRequest(users.alice);
        assertEq(finalPendingShares, 0);
        assertEq(finalPendingAssets, 0);
    }

    function test_AddFundsAndFulfillRedeem_EmitsCorrectEvent() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        vm.roll(block.number + 1);

        // Create redemption request
        createRedemptionRequest(users.alice, shares);

        uint256 initialAggregatedBalance = vault.aggregatedUnderlyingBalances();
        uint256 expectedNewAggregatedBalance = initialAggregatedBalance - assetsWithFee;

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.expectEmit(true, true, true, true);
        emit FundsAddedAndRedemptionFulfilled(users.alice, shares, assetsWithFee, expectedNewAggregatedBalance);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_PartialFulfillment() public {
        uint256 totalShares = getQuantizedValue(20_000);
        uint256 totalAssetsWithoutFee = vault.previewRedeem(totalShares);
        uint256 totalAssetsWithFee = vault.convertToAssets(totalShares);
        uint256 bobTokenBalanceBefore = token.balanceOf(users.bob);

        uint256 totalAssetsBeforeRedemption = vault.totalAssets();
        uint256 totalSupplyBeforeRedemption = vault.totalSupply();

        // Create redemption request for full amount
        createRedemptionRequest(users.bob, totalShares);

        // Fulfill only part of the request
        uint256 partialShares = getQuantizedValue(8000);
        uint256 partialAssetsWithoutFee = vault.previewRedeem(partialShares);
        uint256 partialAssetsWithFee = vault.convertToAssets(partialShares);

        bytes memory data = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector, users.bob, partialShares, partialAssetsWithFee
        );

        vm.startPrank(users.alice); // Alice is fund manager
        vault.manage(address(fundManager), data, 0);

        // Check that partial redemption was processed
        (uint256 remainingAssets, uint256 remainingShares) = vault.pendingRedeemRequest(users.bob);
        assertEq(remainingShares, totalShares - partialShares);
        assertEq(remainingAssets, totalAssetsWithFee - partialAssetsWithFee);

        // Check if bob has received the funds
        assertEq(token.balanceOf(users.bob), bobTokenBalanceBefore + partialAssetsWithoutFee);

        assertEq(vault.totalAssets(), totalAssetsBeforeRedemption - partialAssetsWithFee);
        assertEq(vault.totalSupply(), totalSupplyBeforeRedemption - partialShares);
    }

    function test_AddFundsAndFulfillRedeem_MultipleFulfillments() public {
        uint256 totalShares = getQuantizedValue(30000);
        uint256 totalAssetsWithFee = vault.convertToAssets(totalShares);
        uint256 totalAssetsWithoutFee = vault.previewRedeem(totalShares);

        // Create redemption request
        createRedemptionRequest(users.bob, totalShares);

        // First fulfillment
        uint256 firstShares = getQuantizedValue(10000);
        uint256 firstAssetsWithFee = vault.convertToAssets(firstShares);

        bytes memory data1 = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector, users.bob, firstShares, firstAssetsWithFee
        );

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data1, 0);

        vm.roll(block.number + 1);

        // Second fulfillment
        uint256 secondShares = getQuantizedValue(15000);
        uint256 secondAssetsWithFee = vault.convertToAssets(secondShares);

        bytes memory data2 = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector, users.bob, secondShares, secondAssetsWithFee
        );

        vault.manage(address(fundManager), data2, 0);

        vm.roll(block.number + 1);

        // Check remaining redemption
        (uint256 remainingAssets, uint256 remainingShares) = vault.pendingRedeemRequest(users.bob);
        uint256 expectedRemainingShares = totalShares - firstShares - secondShares;
        assertEq(remainingShares, expectedRemainingShares);

        // Final fulfillment
        uint256 finalShares = remainingShares;
        uint256 finalAssetsWithFee = remainingAssets;

        bytes memory data3 = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector, users.bob, finalShares, finalAssetsWithFee
        );

        vault.manage(address(fundManager), data3, 0);

        // Check all redemptions are completed
        (uint256 finalPendingAssets, uint256 finalPendingShares) = vault.pendingRedeemRequest(users.bob);
        assertEq(finalPendingShares, 0);
        assertEq(finalPendingAssets, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithInvalidSharesAmount() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithFee = vault.previewRedeem(shares);

        // Create redemption request
        createRedemptionRequest(users.bob, shares);

        // Try to fulfill more shares than requested
        uint256 excessiveShares = shares + getQuantizedValue(1000);

        bytes memory data = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector, users.bob, excessiveShares, assetsWithFee
        );

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_RevertsWithInvalidAssetsAmount() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithFee = vault.previewRedeem(shares);

        // Create redemption request
        createRedemptionRequest(users.bob, shares);

        // Try to fulfill with more assets than requested
        uint256 excessiveAssets = assetsWithFee + getQuantizedValue(1000);

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.bob, shares, excessiveAssets);

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidAssetsAmount.selector));
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_MaintainsCorrectBalances() public {
        uint256 shares = getQuantizedValue(15_000);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        // Create redemption request
        createRedemptionRequest(users.bob, shares);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialVaultBalance = token.balanceOf(address(vault));
        uint256 initialAggregatedBalance = vault.aggregatedUnderlyingBalances();

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.bob, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Total assets should decrease by the amount redeemed (minus fees)
        uint256 finalTotalAssets = vault.totalAssets();
        uint256 assetsAfterFee = assetsWithFee - getQuantizedValue(1); // Withdrawal fee is 1 token

        // The total assets should decrease by the net amount given to user
        assertEq(
            finalTotalAssets,
            initialTotalAssets - assetsWithFee,
            "totalAssets() should decrease by the amount distributed"
        );

        // Vault balance should increase by the full assetsWithFee amount
        assertEq(token.balanceOf(address(vault)), initialVaultBalance, "vault's token balance mismatch");

        // Aggregated balance should decrease by assetsWithFee
        assertEq(
            vault.aggregatedUnderlyingBalances(), initialAggregatedBalance - assetsWithFee, "aggregate value mismatch"
        );
    }

    function test_AddFundsAndFulfillRedeem_WithDifferentReceivers() public {
        uint256 shares = getQuantizedValue(8000);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        // Alice creates redemption request but Bob will receive the funds
        createRedemptionRequest(users.alice, shares);

        uint256 initialBobBalance = token.balanceOf(users.alice);

        bytes memory data = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector,
            users.bob, // Different receiver
            shares,
            assetsWithFee
        );

        vm.startPrank(users.alice); // Alice is also fund manager

        // This should revert because the redemption request is for Alice, not Bob
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidSharesAmount.selector));
        vault.manage(address(fundManager), data, 0);
    }

    function test_AddFundsAndFulfillRedeem_CorrectReceiver() public {
        uint256 shares = getQuantizedValue(8000);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        // Alice creates redemption request and should receive the funds
        createRedemptionRequest(users.alice, shares);

        uint256 initialAliceBalance = token.balanceOf(users.alice);

        bytes memory data = abi.encodeWithSelector(
            fundManager.addFundsAndFulfillRedeem.selector,
            users.alice, // Correct receiver
            shares,
            assetsWithFee
        );

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // Alice should receive the assets minus withdrawal fee
        uint256 expectedReceived = assetsWithFee - getQuantizedValue(1); // Minus 1 token withdrawal fee
        assertEq(token.balanceOf(users.alice), initialAliceBalance + expectedReceived);
    }


    function test_addFundsAndFulfillRedeem_SharePriceDoesNotChangeWhenAggregatedBalanceIsNotUpdatedBeforeFulfillRedeem() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        vm.roll(block.number + 1);

        // Create redemption request
        createRedemptionRequest(users.alice, shares);

        uint256 initialLastPricePerShare = vault.lastPricePerShare();

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(initialLastPricePerShare, vault.lastPricePerShare(), "share price has changed");
    }

    function test_addFundsAndFulfillRedeem_SharePriceChangesWhenAggregatedBalanceIsUpdated() public {
        // when yield is added (via `onUnderlyingBalanceUpdate`) to the Vault between requestRedeem and fulfillRedeem 
        // lastSharePrice remains stale
        // this test ensures that lastSharePrice is updated and is in a consistent state
        // side effect of: https://github.com/multipli-libs/MultipliVault?tab=readme-ov-file#temporary-share-price-impact-during-pending-redemptions


        vm.roll(block.number + 1);

        // update underlying balance so price of 1 share is 1.2
        uint256 aggregatedBalance = vault.aggregatedUnderlyingBalances(); // 50_000
        
        uint256 totalAssets = vault.totalAssets(); // 150_000 tokens
        uint256 totalSupply = vault.totalSupply(); // 150_000 tokens

        uint256 newAggregatedBalance = aggregatedBalance + getQuantizedValue(30_000); // increases the share price to 1.2
        
        // assume that you have added 30_000; in yield to the vault
        // this will lead to vault getting paused
        updateUnderlyingBalance(newAggregatedBalance); // 80_000
        unpauseVault();
        vm.roll(block.number + 1);

        // sanity checks to ensure the state of the vaults
        assertEq(vault.totalAssets(), getQuantizedValue(180_000), "totalAssets mimatch");
        assertEq(vault.totalSupply(), getQuantizedValue(150_000), "totalSupply mismatch");
        assertEq(vault.lastPricePerShare(), 12e17, "last price mismatch"); // 1.2 tokens


        // Create redemption request
        // price per share = 1.2
        // amount to be paid out including fee = 6000-1 tokens (note that `1` here is not fee)
        uint256 shares = getQuantizedValue(5000);

        uint256 expectedPendingAssets = vault.convertToAssets(shares); // 5_999_999_999
        assertEq(expectedPendingAssets, getQuantizedValue(6000)-1, "expectedPendingAssets mismatch"); // 5_999_999_999
        createRedemptionRequest(users.alice, shares); // create redemption request
        (uint256 pendingAssets, uint256 pendingShares) = vault.pendingRedeemRequest(users.alice);
        assertEq(pendingAssets, expectedPendingAssets, "pendingRedeem mismatch");

        // aggregateBalance will now be 95_000
        // this will bring the totalAsset value to 195_000
        // and price price will be 1.3 tokens
        updateUnderlyingBalance(newAggregatedBalance + getQuantizedValue(15_000)); 
        unpauseVault();
        vm.roll(block.number + 1);

        assertEq(vault.lastPricePerShare(), 13e17, "last price mismatch after update"); // 1.3 tokens
        assertEq(vault.totalAssets(), getQuantizedValue(195_000), "totalAssets mimatch after update");
        assertEq(vault.totalSupply(), getQuantizedValue(150_000), "totalSupply mismatch after update");

        uint256 initialLastPricePerShare = vault.lastPricePerShare(); // 1.3 tokens

        // redeem 5000 shares
        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, pendingShares, pendingAssets);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        // sanity check to verify the states
        assertEq(vault.totalAssets(), getQuantizedValue(195_000) - pendingAssets, "totalAssets mimatch after redemption"); // 189_000_000_001
        assertEq(vault.totalSupply(), getQuantizedValue(145_000), "totalSupply mismatch after redemption");

        // this is the formula used to calculate `newPricePerShare` in `onUnderlyingBalanceUpdate` in MultipliVault
        uint256 expectedLastPrice = Math.mulDiv(vault.totalAssets(), DENOMINATOR, vault.totalSupply()); // 1.3455....

        assertEq(expectedLastPrice, vault.lastPricePerShare(), "share price mismatch");
        assertGt(expectedLastPrice, initialLastPricePerShare, "share price has not increased");
    }

    function test_addFundsAndFulfillRedeem_BlockNumberIsUpdated() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);

        uint256 blockNumber = block.number + 1;
        vm.roll(blockNumber);

        // Create redemption request
        createRedemptionRequest(users.alice, shares);

        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

        assertEq(blockNumber, vault.lastBlockUpdated(), "Incorrect block number");
    }
}

// This setup does not move out of the funds so aggregate balance will be 0
contract TestAddFundsAndFulfillRedeemDifferentSetup01 is VaultFundManagerBase {
    function setUp() override public {
        super.setUp();

        // Deposit funds into vault for Alice
        depositForUser(users.alice, INITIAL_DEPOSIT);

    }

    function test_addFundsAndFulfillRedeem_Reverts_WhenAssetAmountIsLessThanAggregatedBalance() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);
        
        // Create redemption request
        createRedemptionRequest(users.alice, shares);

        // sanity check
        assertEq(vault.aggregatedUnderlyingBalances(), 0);

        // Call fulfillRedeem
        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("VaultFundManager__InsufficientAggregateUnderlyingBalance()"));
        vault.manage(address(fundManager), data, 0);

    }

    function test_addFundsAndFulfillRedeem_Success_WhenAssetAmountIsEqualToAggregatedBalance() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);
        
        // Create redemption request
        createRedemptionRequest(users.alice, shares);
        
        // update underlying balance
        updateUnderlyingBalance(assetsWithFee);
        vm.roll(block.number + 1);

        // sanity check
        assertEq(vault.aggregatedUnderlyingBalances(), assetsWithFee);

        // Call fulfillRedeem
        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

    }

    function test_addFundsAndFulfillRedeem_Success_WhenAssetAmountGreaterThanAggregatedBalance() public {
        uint256 shares = getQuantizedValue(5000);
        uint256 assetsWithoutFee = vault.previewRedeem(shares);
        uint256 assetsWithFee = vault.convertToAssets(shares);
        
        // Create redemption request
        createRedemptionRequest(users.alice, shares);
        
        // update underlying balance
        uint256 underlyingBalance = assetsWithFee + 1;
        updateUnderlyingBalance(underlyingBalance);
        vm.roll(block.number + 1);

        // sanity check
        assertEq(vault.aggregatedUnderlyingBalances(), underlyingBalance);

        // Call fulfillRedeem
        bytes memory data =
            abi.encodeWithSelector(fundManager.addFundsAndFulfillRedeem.selector, users.alice, shares, assetsWithFee);

        vm.startPrank(users.alice);
        vault.manage(address(fundManager), data, 0);

    }
}