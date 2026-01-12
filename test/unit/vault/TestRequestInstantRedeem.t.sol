// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/libraries/Errors.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";
import {IMultipliVault} from "src/interfaces/IMultipliVault.sol";
import {console} from "forge-std/console.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestRequestInstantRedeem is BaseTest {
    using Math for uint256;

    // ========================================= HELPER CONSTANTS =========================================
    
    uint256 private constant REQUEST_ID = 0;
    uint256 internal amount = 100 * 1e6; // 100 USDC
    uint256 internal aliceShares;
    uint256 internal bobShares;


    function setUp() public override {
        BaseTest.setUp();
        
        // Setup Alice with shares
        vm.startPrank({msgSender: users.alice});
        depositVault.deposit(amount, users.alice);
        aliceShares = depositVault.balanceOf(users.alice);
        vm.stopPrank();

        // Setup Bob with shares
        vm.startPrank({msgSender: users.bob});
        depositVault.deposit(amount, users.bob);
        bobShares = depositVault.balanceOf(users.bob);
        vm.stopPrank();

        // Give Alice external curator privileges for instant redeem testing
        vm.startPrank({msgSender: users.admin});
        MockAuthority(address(authority)).setUserRole(users.alice, EXTERNAL_CURATOR_ROLE, true);
        MockAuthority(address(authority)).setRoleCapability(EXTERNAL_CURATOR_ROLE, address(depositVault), depositVault.requestInstantRedeem.selector, true);
        vm.stopPrank();
    }

    function testRequestInstantRedeemSuccess() public {
        vm.startPrank({msgSender: users.alice});
        
        uint256 sharesBefore = depositVault.balanceOf(users.alice);
        uint256 vaultSharesBefore = depositVault.balanceOf(address(depositVault));
        uint256 totalPendingAssetsBefore = depositVault.totalPendingAssets();
        
        // Calculate expected assets using raw conversion (before any fees)
        uint256 expectedAssetsBeforeFee = depositVault.convertToAssets(aliceShares);
        uint256 expectedFee = expectedAssetsBeforeFee.mulDiv(5e15, 5e15 + 1e18, Math.Rounding.Ceil); // 0.5% fee using "fee on total" formula
        uint256 expectedAssetsAfterFee = expectedAssetsBeforeFee - expectedFee;
        
        // Expect InstantRedeemRequest event
        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.InstantRedeemRequest(users.alice, users.alice, expectedAssetsBeforeFee, aliceShares);
        
        uint256 requestId = depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
        
        // Verify state changes
        assertEq(requestId, REQUEST_ID, "Request ID should be 0");
        assertEq(depositVault.balanceOf(users.alice), 0, "Alice should have 0 shares after request");
        assertEq(depositVault.balanceOf(address(depositVault)), vaultSharesBefore + aliceShares, "Vault should hold Alice's shares");
        assertEq(depositVault.totalPendingAssets(), totalPendingAssetsBefore + expectedAssetsBeforeFee, "Total pending assets should increase");
        
        // Check pending request
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingAssets, expectedAssetsBeforeFee, "Pending assets should match expected");
        assertEq(pendingShares, aliceShares, "Pending shares should match requested shares");
    }

    function testRequestInstantRedeemPartialShares() public {
        vm.startPrank({msgSender: users.alice});
        
        uint256 partialShares = aliceShares / 2; // Request half
        uint256 expectedAssetsBeforeFee = depositVault.convertToAssets(partialShares);
        
        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.InstantRedeemRequest(users.alice, users.alice, expectedAssetsBeforeFee, partialShares);
        
        depositVault.requestInstantRedeem(partialShares, users.alice, users.alice);
        
        // Verify Alice still has remaining shares
        assertEq(depositVault.balanceOf(users.alice), aliceShares - partialShares, "Alice should have remaining shares");
        
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingShares, partialShares, "Pending shares should match partial amount");
        assertEq(pendingAssets, depositVault.convertToAssets(partialShares), "Pending assets should match partial amount");
    }

    function testRequestInstantRedeemMultipleRequests() public {
        vm.startPrank({msgSender: users.alice});
        
        uint256 firstRequest = aliceShares / 3;
        uint256 secondRequest = aliceShares / 3;
        
        // First request
        depositVault.requestInstantRedeem(firstRequest, users.alice, users.alice);
        (uint256 pendingAssets1, uint256 pendingShares1) = depositVault.pendingRedeemRequest(users.alice);
        
        // Second request - should accumulate
        depositVault.requestInstantRedeem(secondRequest, users.alice, users.alice);
        (uint256 pendingAssets2, uint256 pendingShares2) = depositVault.pendingRedeemRequest(users.alice);
        
        assertEq(pendingShares2, pendingShares1 + secondRequest, "Pending shares should accumulate");
        assertEq(pendingAssets2, pendingAssets1 + depositVault.convertToAssets(secondRequest), "Pending assets should match and accumulate");
        assertTrue(pendingAssets2 > pendingAssets1, "Pending assets should accumulate");
    }

    function testRequestInstantRedeemDifferentReceiver() public {
        vm.startPrank({msgSender: users.alice});
        
        uint256 expectedAssetsBeforeFee = depositVault.convertToAssets(aliceShares);
        
        vm.expectEmit(true, true, false, true);
        emit IMultipliVault.InstantRedeemRequest(users.bob, users.alice, expectedAssetsBeforeFee, aliceShares);

        uint256 expectedAssetAmount = depositVault.convertToAssets(aliceShares);
    
        depositVault.requestInstantRedeem(aliceShares, users.bob, users.alice);
        
        // Check that pending request is stored under receiver (Bob), not owner (Alice)
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.bob);
        assertEq(pendingShares, aliceShares, "Pending shares should be under receiver address");
        assertEq(pendingAssets, expectedAssetAmount, "Pending assets should be under receiver address");
        
        // Alice should have no pending request
        (uint256 alicePendingAssets, uint256 alicePendingShares) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(alicePendingShares, 0, "Alice should have no pending shares");
        assertEq(alicePendingAssets, 0, "Alice should have no pending assets");
    }

    // ========================================= REVERT TESTS =========================================

    function testRequestInstantRedeemRevertsOnUnauthorized() public {
        // Remove Alice's curator role
        vm.startPrank({msgSender: users.admin});
        MockAuthority(address(authority)).setUserRole(users.alice, EXTERNAL_CURATOR_ROLE, false);
        vm.stopPrank();
        
        vm.startPrank({msgSender: users.alice});
        vm.expectRevert("UNAUTHORIZED");
        depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
    }

    function testRequestInstantRedeemRegularUserCannotCall() public {
        // Bob is a regular user without curator privileges
        vm.startPrank({msgSender: users.bob});
        
        // First, Bob gets some shares
        depositVault.deposit(amount, users.bob);
        uint256 bobShares = depositVault.balanceOf(users.bob);
        
        // Bob should not be able to call instant redeem without curator role
        vm.expectRevert("UNAUTHORIZED");
        depositVault.requestInstantRedeem(bobShares, users.bob, users.bob);
    }

    function testRequestInstantRedeemMultipleCurators() public {
        // Setup Bob as another curator
        vm.startPrank({msgSender: users.admin});
        MockAuthority(address(authority)).setUserRole(users.bob, EXTERNAL_CURATOR_ROLE, true);
        vm.stopPrank();
        
        // Bob gets some shares
        vm.startPrank({msgSender: users.bob});
        depositVault.deposit(amount, users.bob);
        uint256 bobShares = depositVault.balanceOf(users.bob);
        
        // Both Alice and Bob should be able to call instant redeem
        vm.startPrank({msgSender: users.alice});
        depositVault.requestInstantRedeem(aliceShares / 2, users.alice, users.alice);
        
        vm.startPrank({msgSender: users.bob});
        depositVault.requestInstantRedeem(bobShares / 2, users.bob, users.bob);
        
        // Verify both have pending requests
        (uint256 alicePendingAssets, uint256 alicePendingShares) = depositVault.pendingRedeemRequest(users.alice);
        (uint256 bobPendingAssets, uint256 bobPendingShares) = depositVault.pendingRedeemRequest(users.bob);
        
        assertTrue(alicePendingShares > 0, "Alice should have pending shares");
        assertTrue(bobPendingShares > 0, "Bob should have pending shares");

        assertTrue(alicePendingShares == aliceShares / 2, "Alice pending shares mismatch");
        assertTrue(bobPendingShares == bobShares / 2, "Bob pending shares mismatch");
    }

    function testRequestInstantRedeemRevertsOnZeroShares() public {
        vm.startPrank({msgSender: users.alice});
        vm.expectRevert(abi.encodeWithSelector(Errors.SharesAmountZero.selector));
        depositVault.requestInstantRedeem(0, users.alice, users.alice);
    }

    function testRequestInstantRedeemRevertsOnNotOwner() public {
        // Add bob to `EXTERNAL_CURATOR_ROLE` role, so bob can now call `requestInstantRedeem`
        vm.startPrank(users.admin);
        MockAuthority(address(authority)).setUserRole(users.bob, EXTERNAL_CURATOR_ROLE, true);
        vm.stopPrank();

        vm.startPrank({msgSender: users.bob});
        vm.expectRevert(abi.encodeWithSelector(Errors.NotSharesOwner.selector));
        depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
    }

    function testRequestInstantRedeemRevertsOnInsufficientShares() public {
        vm.startPrank({msgSender: users.alice});
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientShares.selector));
        depositVault.requestInstantRedeem(aliceShares + 1, users.alice, users.alice);
    }

    function testRequestInstantRedeemRevertsWhenPaused() public {
        vm.startPrank({msgSender: users.admin});
        depositVault.pause();
        vm.stopPrank();
        
        vm.startPrank({msgSender: users.alice});
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
    }

    // ========================================= EDGE CASES =========================================

    function testRequestInstantRedeemWithMaxShares() public {
        // Test with maximum possible shares (Alice's full balance)
        vm.startPrank({msgSender: users.alice});
        uint256 maxShares = depositVault.balanceOf(users.alice);
        
        uint256 expectedAssets = depositVault.convertToAssets(maxShares);

        depositVault.requestInstantRedeem(maxShares, users.alice, users.alice);
        
        assertEq(depositVault.balanceOf(users.alice), 0, "Alice should have 0 shares after max request");
        
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingShares, maxShares, "All shares should be pending");
        assertEq(pendingAssets, expectedAssets, "asset mismatch");
    }

    function testRequestInstantRedeemWithMinShares() public {
        vm.startPrank({msgSender: users.alice});
        uint256 minShares = 1; // Smallest possible amount

        uint256 expectedAssets = depositVault.convertToAssets(minShares);
        
        if (aliceShares >= minShares) {
            depositVault.requestInstantRedeem(minShares, users.alice, users.alice);
            
            (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(users.alice);
            assertEq(pendingShares, minShares, "Min shares should be pending");
            assertEq(pendingAssets, expectedAssets, "Min assets should be pending");
        }
    }

    function testRequestInstantRedeemAfterTransfer() public {
        // Transfer some shares to Bob first
        vm.startPrank({msgSender: users.alice});
        uint256 transferAmount = aliceShares / 2;
        depositVault.transfer(users.bob, transferAmount);
        
        // Now Alice can only redeem remaining shares
        uint256 remainingShares = depositVault.balanceOf(users.alice);
        depositVault.requestInstantRedeem(remainingShares, users.alice, users.alice);
        
        assertEq(depositVault.balanceOf(users.alice), 0, "Alice should have 0 shares after request");
    }

    // ========================================= FEE CALCULATION TESTS =========================================

    function testRequestInstantRedeemFeeCalculation() public {
        vm.startPrank({msgSender: users.alice});
        
        uint256 expectedAssetsBeforeFee = depositVault.convertToAssets(aliceShares);
        uint256 expectedAssetsAfterFee = depositVault.previewInstantRedeem(aliceShares);
        uint256 expectedFee = expectedAssetsBeforeFee - expectedAssetsAfterFee;

        assertEq(expectedFee, Math.mulDiv(expectedAssetsBeforeFee, 5e15, 5e15 + 1e18, Math.Rounding.Ceil));
        
        depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
        
        (uint256 pendingAssets,) = depositVault.pendingRedeemRequest(users.alice);
        
        // Pending assets should be before fee deduction (fee is deducted during fulfillment)
        assertEq(pendingAssets, expectedAssetsBeforeFee, "Pending assets should be before fee deduction");
        
        // Verify fee calculation is reasonable (with "fee on total" formula: 5e15/(5e15+1e18) ≈ 4.975e15)
        uint256 calculatedFeeRate = expectedFee.mulDiv(1e18, expectedAssetsBeforeFee);
        uint256 expectedEffectiveRate = uint256(5e15).mulDiv(1e18, 5e15 + 1e18); // ≈ 4.975e15
        assertApproxEqAbs(calculatedFeeRate, expectedEffectiveRate, 1e12, "Fee rate should match fee-on-total calculation");
    }

    // ========================================= INTEGRATION TESTS =========================================

    function testRequestInstantRedeemWithPriceChange() public {
        // console.log("number of shares: ", depositVault.balanceOf(users.alice));
        uint256 amountInVault = usdc.balanceOf(address(depositVault));
        // Simulate a price change by updating underlying balance
        moveAssetsFromVault(amountInVault / 2); // Move half the assets out but underlying balance is not updated
        vm.roll(block.number + 1);
        updateUnderlyingBalance((amountInVault + 1) / 2); // Update to reflect new balance
        // vm.roll(block.number + 1);
        // updateUnderlyingBalance(10);
        
        vm.startPrank({msgSender: users.alice});
        
        uint256 expectedAssetsBeforeFee = depositVault.convertToAssets(aliceShares);
        depositVault.requestInstantRedeem(aliceShares, users.alice, users.alice);
        
        (uint256 pendingAssets,) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingAssets, expectedAssetsBeforeFee, "Pending assets should reflect current price");
    }

    function testRequestInstantRedeemSequentialRequests() public {
        vm.startPrank(users.admin);
        // Set permission for ADMIN to call `fulfillInstantRedeem`
        MockAuthority(address(authority)).setRoleCapability(ADMIN_ROLE, address(depositVault), depositVault.fulfillInstantRedeem.selector, true);
        vm.stopPrank();


        vm.startPrank({msgSender: users.alice});
        // Create initial request
        uint256 firstShares = aliceShares / 3;
        depositVault.requestInstantRedeem(firstShares, users.alice, users.alice);
        
        // Fulfill the first request
        vm.startPrank({msgSender: users.admin});
        (uint256 pendingAssets1, uint256 pendingShares1) = depositVault.pendingRedeemRequest(users.alice);
        depositVault.fulfillInstantRedeem(users.alice, pendingShares1, pendingAssets1);
        
        // Make second request with remaining shares
        vm.startPrank({msgSender: users.alice});
        uint256 remainingShares = depositVault.balanceOf(users.alice);
        uint256 expectedAssets2 = depositVault.convertToAssets(remainingShares);
        depositVault.requestInstantRedeem(remainingShares, users.alice, users.alice);
        
        (uint256 pendingAssets2, uint256 pendingShares2) = depositVault.pendingRedeemRequest(users.alice);
        assertEq(pendingShares2, remainingShares, "Second request should only include remaining shares");
        assertEq(pendingAssets2, expectedAssets2, "Second request should only include remaining shares");
    }

    // ========================================= SECURITY TESTS =========================================

    function testRequestInstantRedeemCannotStealOtherShares() public {
        // Bob tries to redeem Alice's shares
        vm.startPrank({msgSender: users.admin});
        MockAuthority(address(authority)).setUserRole(users.bob, EXTERNAL_CURATOR_ROLE, true);
        vm.stopPrank();
        
        vm.startPrank({msgSender: users.bob});
        
        // Bob should not be able to redeem Alice's shares
        vm.expectRevert(abi.encodeWithSelector(Errors.NotSharesOwner.selector));
        depositVault.requestInstantRedeem(aliceShares, users.bob, users.alice);
    }

}