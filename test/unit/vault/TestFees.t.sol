// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {VaultFeeUpgradeable} from "src/base/VaultFeeUpgradeable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {MockVariableVaultFee} from "../../mocks/MockVariableVaultFee.sol";

import {Errors} from "src/libraries/Errors.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract TestVaultFeeOperations is BaseTest {
    // Fee contract and related variables
    address internal feeRecipient;

    // Test users
    address internal alice;
    address internal bob;
    address internal charlie;

    // Constants for fee testing
    uint256 internal FLAT_FEE_AMOUNT;
    uint256 internal constant PERCENTAGE_FEE_5_PERCENT = 5e16; // 5%
    uint256 internal constant PERCENTAGE_FEE_1_PERCENT = 1e16; // 1%
    uint256 internal constant PERCENTAGE_FEE_05_PERCENT = 5e15; // 0.5%

    // Test amounts
    uint256 internal DEPOSIT_AMOUNT_SMALL;
    uint256 internal DEPOSIT_AMOUNT_MEDIUM;
    uint256 internal DEPOSIT_AMOUNT_LARGE;

    bytes4 internal originalMintSelector = bytes4(keccak256("mint(uint256,address)"));
    bytes4 internal originalDepositSelector = bytes4(keccak256("deposit(uint256,address)"));

    function setUp() public override {
        BaseTest.setUp();

        FLAT_FEE_AMOUNT = getQuantizedValue(100); // 100 tokens flat fee

        DEPOSIT_AMOUNT_SMALL = getQuantizedValue(1000); 
        DEPOSIT_AMOUNT_MEDIUM = getQuantizedValue(10000); 
        DEPOSIT_AMOUNT_LARGE = getQuantizedValue(100000); 

        // Set up test users
        alice = users.alice;
        bob = users.bob;
        charlie = makeAddr("Charlie");
        feeRecipient = users.feeRecipient;

        // Deploy fee contract
        feeContract = new VariableVaultFee(users.admin);

        // Set fee contract in vault
        vm.startPrank(users.admin);
        depositVault.setFeeContract(feeContract);
        vm.stopPrank();

        // Fund test users with tokens
        _fundUsers();
    }

    function _fundUsers() internal {
        // Fund users
        deal(address(token), alice, getQuantizedValue(1_000_000)); // 1M tokens
        deal(address(token), bob, getQuantizedValue(1_000_000)); // 1M tokens
        deal(address(token), charlie, getQuantizedValue(1_000_000)); // 1M tokens

        require(token.balanceOf(alice) == getQuantizedValue(1_000_000), "Pre-requisite balance check failed"); // 1M tokens
        require(token.balanceOf(bob) == getQuantizedValue(1_000_000), "Pre-requisite balance check failed"); // 1M tokens
        require(token.balanceOf(charlie) == getQuantizedValue(1_000_000), "Pre-requisite balance check failed"); // 1M tokens
    }

    function _setupFlatFeeConfig() internal returns (IVariableVaultFee.AssetFeeConfig memory) {
        return IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            feeRecipient: feeRecipient
        });
    }

    function _setupPercentageFeeConfig(uint256 depositFeePercent, uint256 withdrawalFeePercent, uint256 instantWithdrawalFeePercent, uint256 flashRedeemFee)
        internal
        returns (IVariableVaultFee.AssetFeeConfig memory)
    {
        return IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: depositFeePercent
            }),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: withdrawalFeePercent
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: instantWithdrawalFeePercent
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: flashRedeemFee
            }),
            feeRecipient: feeRecipient
        });
    }

    function _registerAssetWithFees(IVariableVaultFee.AssetFeeConfig memory assetConfig) internal {
        vm.startPrank(users.admin);
        feeContract.registerAsset(address(token), assetConfig);
        vm.stopPrank();
    }

    // ========================================= DEPOSIT TESTS =========================================

    function test_deposit_Success_WithFlatFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;
        uint256 expectedFee = FLAT_FEE_AMOUNT;
        uint256 expectedAssetsAfterFee = depositAmount - expectedFee;

        // Pre-state
        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);
        uint256 vaultTokensBefore = token.balanceOf(address(depositVault));

        // Sanity checks
        {
            require(aliceTokensBefore == getQuantizedValue(1_000_000), "Alice balance does not match expectation");
            require(feeRecipientBefore == 0, "feeRecipientBefore balance does not match expectation");
            require(vaultTokensBefore == 0, "Vault balance does not match expectation");
        }

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        // make sure that Deposit event is emitted
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, depositAmount, expectedAssetsAfterFee);

        // Execute deposit
        uint256 sharesReceived = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Post-state checks
        assertEq(token.balanceOf(alice), aliceTokensBefore - depositAmount, "Alice should pay full deposit amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore + expectedFee, "Fee recipient should receive fee");
        assertEq(
            token.balanceOf(address(depositVault)),
            vaultTokensBefore + expectedAssetsAfterFee,
            "Vault should receive assets after fee"
        );
        assertEq(depositVault.balanceOf(alice), sharesReceived, "Alice should receive shares");

        // Sanity check to ensure alice received correct number of shares
        assertEq(depositVault.balanceOf(alice), getQuantizedValue(9_900), "Alice should receive shares");

        // Verify shares calculation
        uint256 expectedShares = depositVault.convertToShares(expectedAssetsAfterFee);
        assertEq(sharesReceived, expectedShares, "Shares should match expected amount after fee deduction");
    }

    function test_deposit_Success_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;
        uint256 expectedFee =
            Math.mulDiv(depositAmount, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil);
        uint256 expectedAssetsAfterFee = depositAmount - expectedFee;


        // Pre-state
        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        // make sure that Deposit event is emitted
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, depositAmount, expectedAssetsAfterFee);

        uint256 sharesReceived = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Sanity check for shares received
        assertEq(sharesReceived, depositAmount - expectedFee); // depositAmount - fee = 10_000e6 - 99009901

        // Post-state checks
        assertEq(token.balanceOf(alice), aliceTokensBefore - depositAmount, "Alice should pay full deposit amount");
        assertEq(
            token.balanceOf(feeRecipient),
            feeRecipientBefore + expectedFee,
            "Fee recipient should receive correct percentage fee"
        );

        // Verify shares match preview
        uint256 previewShares = depositVault.previewDeposit(depositAmount);
        assertEq(sharesReceived, previewShares, "Shares should match preview amount");
    }

    function test_deposit_Success_WithZeroFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupPercentageFeeConfig(0, 0, 0, 0);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, depositAmount, depositAmount);

        uint256 sharesReceived = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Sanity check for shares received
        assertEq(sharesReceived, getQuantizedValue(10_000)); // depositAmount - fee = getQuantizedValue(10_000);

        // No fee should be charged
        assertEq(token.balanceOf(alice), aliceTokensBefore - depositAmount, "Alice should pay deposit amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore, "No fee should be charged");
        assertEq(token.balanceOf(address(depositVault)), depositAmount, "Vault should receive full amount");
    }

    function test_deposit_Reverts_WithZeroAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = 0;

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);
        uint256 sharesReceived = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // no changes made to balances
        assertEq(token.balanceOf(alice), aliceTokensBefore, "No change in amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore, "No fee should be charged");
        assertEq(token.balanceOf(address(depositVault)), 0, "No funds added to the vault");
    }

    function test_deposit_Reverts_WhenFeeNotConfigured() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.prank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(0)));

        assertEq(address(depositVault.feeContract()), address(0));

        uint256 depositAmount = 0;

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                VaultFeeUpgradeable.VaultFee__ConfiguredIncorrectly.selector, 
                originalDepositSelector
        ));
        uint256 sharesReceived = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // no changes made to balances
        assertEq(token.balanceOf(alice), aliceTokensBefore, "No change in amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore, "No fee should be charged");
        assertEq(token.balanceOf(address(depositVault)), 0, "No funds added to the vault");
    }

    function test_deposit_RevertsWhen_VaultPaused() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        // Pause vault
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    function test_deposit_RevertsWhen_InsufficientAllowance() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        // Approve less than required
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM - 1);

        vm.expectRevert();
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    // ========================================= MINT TESTS =========================================

    function test_mint_Success_WithFlatFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 vaultBalanceBefore = token.balanceOf(address(depositVault));
        assertEq(vaultBalanceBefore, 0);
        assertEq(depositVault.totalSupply(), 0);
        assertEq(depositVault.totalAssets(), 0);

        uint256 sharesToMint = getQuantizedValue(1000);
        uint256 expectedAssets = depositVault.previewMint(sharesToMint);
        uint256 expectedFee = getQuantizedValue(100); // flat fee -> hardcoded

        // Sanity check
        // Fee will be added on top of the assets (calculated from shares)
        assertEq(expectedAssets, sharesToMint + expectedFee);
        assertEq(expectedAssets, getQuantizedValue(1100));

        vm.startPrank(alice);
        token.approve(address(depositVault), expectedAssets);

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, expectedAssets, sharesToMint);

        uint256 assetsUsed = depositVault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(assetsUsed, expectedAssets, "Assets used should match preview");
        assertEq(depositVault.balanceOf(alice), sharesToMint, "Alice should receive exact shares requested");
        assertEq(token.balanceOf(alice), aliceTokensBefore - assetsUsed, "Alice should pay correct amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore + expectedFee, "Fee recipient should receive fee");

        assertEq(token.balanceOf(address(depositVault)), vaultBalanceBefore + expectedAssets - expectedFee);
        assertEq(token.balanceOf(address(depositVault)), 0 + getQuantizedValue(1100) - getQuantizedValue(100)); // sanity check for above statement
    }

    function test_mint_Success_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT);
        _registerAssetWithFees(assetConfig);

        // pre-requisites
        uint256 vaultBalanceBefore = token.balanceOf(address(depositVault));
        assertEq(vaultBalanceBefore, 0);
        assertEq(depositVault.totalSupply(), 0);
        assertEq(depositVault.totalAssets(), 0);

        uint256 sharesToMint = getQuantizedValue(5000);
        uint256 previewAssets = depositVault.previewMint(sharesToMint);
        uint256 expectedFee = getQuantizedValue(25);

        // sanity checks
        assertEq(previewAssets, sharesToMint + expectedFee); // getQuantizedValue(5025);
        assertEq(previewAssets, getQuantizedValue(5025));

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, previewAssets, sharesToMint);

        uint256 assetsUsed = depositVault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(assetsUsed, previewAssets, "Assets used should match preview");
        assertEq(depositVault.balanceOf(alice), sharesToMint, "Alice should receive exact shares");
        assertEq(token.balanceOf(alice), aliceTokensBefore - assetsUsed, "Alice should pay correct amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore + expectedFee, "Fee recipient should receive fee");

        assertEq(token.balanceOf(address(depositVault)), vaultBalanceBefore + previewAssets - expectedFee);
        assertEq(token.balanceOf(address(depositVault)), 0 + getQuantizedValue(5025) - getQuantizedValue(25)); // sanity check for above statement
    }

    function test_mint_Success_WithZeroShares() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT);
        _registerAssetWithFees(assetConfig);

        // pre-requisites
        uint256 vaultBalanceBefore = token.balanceOf(address(depositVault));
        assertEq(vaultBalanceBefore, 0);
        assertEq(depositVault.totalSupply(), 0);
        assertEq(depositVault.totalAssets(), 0);

        uint256 sharesToMint = 0;

        vm.expectRevert(abi.encodeWithSignature("IVariableVaultFee__ZeroAmount()"));
        uint256 previewAssets = depositVault.previewMint(sharesToMint);

        uint256 expectedFee = 0;

        // sanity checks
        assertEq(previewAssets, sharesToMint + expectedFee); // getQuantizedValue(5025);

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);

        vm.expectRevert(abi.encodeWithSignature("IVariableVaultFee__ZeroAmount()"));
        uint256 assetsUsed = depositVault.mint(sharesToMint, alice);
        vm.stopPrank();
    }

    function test_mint_RevertsWhen_VaultPaused() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        depositVault.mint(getQuantizedValue(1000), alice);
        vm.stopPrank();
    }

    function test_mint_Reverts_WhenFeeNotConfigured() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.prank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(0)));

        assertEq(address(depositVault.feeContract()), address(0));

        uint256 depositAmount = 0;

        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(VaultFeeUpgradeable.VaultFee__ConfiguredIncorrectly.selector, originalMintSelector)
        );
        uint256 sharesReceived = depositVault.mint(depositAmount, alice);
        vm.stopPrank();

        // no changes made to balances
        assertEq(token.balanceOf(alice), aliceTokensBefore, "No change in amount");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBefore, "No fee should be charged");
        assertEq(token.balanceOf(address(depositVault)), 0, "No funds added to the vault");
    }

    // ========================================= REQUEST REDEEM TESTS =========================================

    function test_requestRedeem_Success_WithFlatFee() public {
        // First setup and deposit
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        // Now test redeem request
        uint256 sharesToRedeem = shares / 2;
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(sharesToRedeem);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(sharesToRedeem);

        uint256 aliceSharesBefore = depositVault.balanceOf(alice);
        uint256 vaultSharesBefore = depositVault.balanceOf(address(depositVault));
        uint256 totalPendingBefore = depositVault.totalPendingAssets();

        uint256 requestId = depositVault.requestRedeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        // Verify request was created correctly
        assertEq(requestId, 0, "Request ID should be 0");
        assertEq(depositVault.balanceOf(alice), aliceSharesBefore - sharesToRedeem, "Alice shares should decrease");
        assertEq(
            depositVault.balanceOf(address(depositVault)),
            vaultSharesBefore + sharesToRedeem,
            "Vault should hold shares"
        );
        assertEq(
            depositVault.totalPendingAssets(),
            totalPendingBefore + expectedAssetsWithFee,
            "Pending assets should increase"
        );

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, expectedAssetsWithFee, "Pending assets should match expected");
        assertEq(pendingShares, sharesToRedeem, "Pending shares should match requested");
    }

    function test_requestRedeem_Success_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_LARGE;
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = shares;
        uint256 expectedAssets = depositVault.previewRedeem(sharesToRedeem); // does not include fee
        uint256 expectedAssetWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 fee = expectedAssetWithFee - expectedAssets;

        depositVault.requestRedeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, expectedAssets + fee, "Pending assets should include fee calculation");
        assertEq(pendingShares, sharesToRedeem, "All shares should be pending");
    }

    function test_requestRedeem_RevertsWhen_ZeroShares() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        vm.expectRevert(Errors.Errors__SharesAmountZero.selector); // Should revert with SharesAmountZero
        depositVault.requestRedeem(0, alice, alice);
        vm.stopPrank();
    }

    function test_requestRedeem_RevertsWhen_NotOwner() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Bob tries to redeem Alice's shares
        vm.startPrank(bob);
        vm.expectRevert(Errors.Errors__NotSharesOwner.selector); // Should revert with NotSharesOwner
        depositVault.requestRedeem(shares, bob, alice);
        vm.stopPrank();
    }

    function test_requestRedeem_RevertsWhen_InsufficientShares() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_SMALL);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_SMALL, alice);

        vm.expectRevert(Errors.Errors__InsufficientShares.selector); // Should revert with InsufficientShares
        depositVault.requestRedeem(shares + 1, alice, alice);
        vm.stopPrank();
    }

    function test_requestRedeem_RevertsWhen_VaultPaused() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Pause vault
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();
    }

    // ========================================= FULFILL REDEEM TESTS =========================================

    function test_fulfillRedeem_Success_WithFlatFee() public {
        // Setup and create redeem request
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = shares / 2;
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(sharesToRedeem);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 expectedFee = FLAT_FEE_AMOUNT;
        assertEq(
            FLAT_FEE_AMOUNT,
            expectedAssetsWithFee - expectedAssetsWithoutFee,
            "expected fee does not match with calculated fee"
        );
        depositVault.requestRedeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        // Fund vault with assets for redemption
        deal(address(token), address(depositVault), expectedAssetsWithFee);

        // Fulfill the request
        uint256 aliceTokensBefore = token.balanceOf(alice);
        uint256 feeRecipientBefore = token.balanceOf(feeRecipient);
        uint256 vaultSharesBefore = depositVault.balanceOf(address(depositVault));
        uint256 totalSupplyBefore = depositVault.totalSupply();

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, sharesToRedeem, expectedAssetsWithFee);
        vm.stopPrank();

        // Verify fulfillment
        assertEq(
            depositVault.balanceOf(address(depositVault)),
            vaultSharesBefore - sharesToRedeem,
            "Vault shares should decrease"
        );
        assertEq(depositVault.totalSupply(), totalSupplyBefore - sharesToRedeem, "Total supply should decrease");
        assertEq(token.balanceOf(alice), aliceTokensBefore + expectedAssetsWithoutFee, "Alice should receive assets");
        assertEq(
            token.balanceOf(feeRecipient),
            feeRecipientBefore + expectedFee,
            "Fee recipient should receive withdrawal fee"
        );

        // Check pending request is cleared
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, 0, "No pending assets should remain");
        assertEq(pendingShares, 0, "No pending shares should remain");
    }

    function test_fulfillRedeem_Success_PartialFulfillment() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        // Create large redeem request
        uint256 depositAmount = DEPOSIT_AMOUNT_LARGE;
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        uint256 totalAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 totalAssetsWithFee = depositVault.convertToAssets(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Fulfill only half
        uint256 sharesToFulfill = shares / 2;
        uint256 assetsToFulfill = totalAssetsWithFee / 2;

        // ensure vault has enough funds
        deal(address(token), address(depositVault), assetsToFulfill);

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, sharesToFulfill, assetsToFulfill);
        vm.stopPrank();

        // Check remaining pending request
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingShares, shares - sharesToFulfill, "Half shares should remain pending");
        assertEq(pendingAssets, totalAssetsWithFee - assetsToFulfill, "Half assets should remain pending");
    }

    function test_fulfillRedeem_RevertsWhen_InvalidSharesAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssets = depositVault.previewRedeem(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        vm.startPrank(users.admin);
        vm.expectRevert(); // Should revert with InvalidSharesAmount
        depositVault.fulfillRedeem(alice, shares + 1, expectedAssets);
        vm.stopPrank();
    }

    function test_fulfillRedeem_RevertsWhen_InvalidAssetsAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        vm.startPrank(users.admin);
        vm.expectRevert(Errors.Errors__InvalidAssetsAmount.selector); // Should revert with InvalidAssetsAmount
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee + 1);
        vm.stopPrank();
    }

    function test_fulfillRedeem_RevertsWhen_UnauthorizedUser() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssets = depositVault.previewRedeem(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.fulfillRedeem(alice, shares, expectedAssets);
        vm.stopPrank();
    }

    // todo: When running fulfill Redeem, there is a possibility that you could
    // specify the incorrect number of assets for the corresponding number\
    // of shares or vice-versa
    // Eg: Let's assume that a user initiates a requestRedeem for 100 shares.
    // Let's assume the asset value is 100. When fulfilling the redeem, it's
    // possible for admin to call 100 shares with 50 as asset value.

    // ========================================= CANCEL REDEEM TESTS =========================================

    function test_cancelRedeem_Success() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        // Create redeem request
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssets = depositVault.previewRedeem(shares);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(shares);
        uint256 fee = expectedAssetsWithFee - expectedAssets;

        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Cancel the request
        uint256 aliceSharesBefore = depositVault.balanceOf(alice);
        uint256 totalPendingBefore = depositVault.totalPendingAssets();

        vm.startPrank(users.admin);
        depositVault.cancelRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Verify cancellation
        assertEq(depositVault.balanceOf(alice), aliceSharesBefore + shares, "Alice should get shares back");
        assertEq(
            depositVault.totalPendingAssets(),
            totalPendingBefore - expectedAssetsWithFee,
            "Pending assets should decrease"
        );

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, 0, "No pending assets should remain");
        assertEq(pendingShares, 0, "No pending shares should remain");
    }

    function test_cancelRedeem_Success_PartialCancel() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_LARGE, alice);
        uint256 totalAssets = depositVault.previewRedeem(shares);
        uint256 totalAssetsWithFee = depositVault.convertToAssets(shares);
        uint256 totalFee = totalAssetsWithFee - totalAssets;

        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Cancel half
        uint256 sharesToCancel = shares / 2;
        uint256 assetsToCancel = totalAssets / 2;

        vm.startPrank(users.admin);
        depositVault.cancelRedeem(alice, sharesToCancel, assetsToCancel);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingShares, shares - sharesToCancel, "Half shares should remain pending");
        assertEq(pendingAssets, totalAssetsWithFee - assetsToCancel, "Half assets should remain pending");
    }

    function test_cancelRedeem_RevertsWhen_UnauthorizedUser() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssets = depositVault.previewRedeem(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.cancelRedeem(alice, shares, expectedAssets);
        vm.stopPrank();
    }

    function test_flatWithdrawalFee_unchangedDuringPendingRedeem_usesOriginalFeeAtFulfillment() public {
        // Setup: 0 deposit fee, 100 tokens withdrawal fee
        IVariableVaultFee.AssetFeeConfig memory initialConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(100) // 100 tokens
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(100) // 100 tokens
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(100) // 100 tokens
            }),
            feeRecipient: feeRecipient
        });
        _registerAssetWithFees(initialConfig);

        // User deposits 200 tokens
        uint256 depositAmount = getQuantizedValue(200);
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        // User initiates requestRedeem
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(shares); // Should be 200 - 100 = 100 tokens
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(shares);
        uint256 fee = expectedAssetsWithFee - expectedAssetsWithoutFee;
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        (uint256 storedAssets, uint256 storedShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(storedAssets, expectedAssetsWithFee, "Should store assets with original fee");

        // Fee remains unchanged (100 tokens) - no update needed

        // Admin fulfills redeem
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        deal(address(token), address(depositVault), expectedAssetsWithFee);

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Verify: Alice gets assets minus current fee (100 tokens)
        uint256 currentFee = getQuantizedValue(100);
        uint256 assetsToAlice = expectedAssetsWithFee - currentFee;

        assertEq(
            token.balanceOf(alice), aliceBalanceBefore + assetsToAlice, "Alice should receive assets minus current fee"
        );
        assertEq(
            token.balanceOf(feeRecipient), feeRecipientBalanceBefore + currentFee, "Fee recipient should get current fee"
        );
    }

    function test_flatWithdrawalFee_increasedFrom100To200Tokens_duringPendingRedeem_usesNewFeeAtFulfillment() public {
        // Setup: 0 deposit fee, 100 tokens withdrawal fee
        IVariableVaultFee.AssetFeeConfig memory initialConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(100)}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(100)}),
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(100)}),
            feeRecipient: feeRecipient
        });
        _registerAssetWithFees(initialConfig);

        // User deposits 200 tokens
        uint256 depositAmount = getQuantizedValue(200);
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        assertEq(shares, getQuantizedValue(200));

        // User initiates requestRedeem (with 100 tokens fee)
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 expectedAssetWithFee = depositVault.convertToAssets(shares);
        uint256 fee = expectedAssetWithFee - expectedAssetsWithoutFee;

        assertEq(fee, getQuantizedValue(100));

        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, getQuantizedValue(200));
        assertEq(pendingShares, getQuantizedValue(200));

        // Update withdrawal fee to 200 tokens
        IVariableVaultFee.AssetFeeConfig memory updatedConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(200) // Updated to 200 tokens
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(200) // Updated to 200 tokens
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(200) // Updated to 200 tokens
            }),
            feeRecipient: feeRecipient
        });

        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(address(token), updatedConfig);
        vm.stopPrank();

        // Admin fulfills redeem
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        deal(address(token), address(depositVault), expectedAssetsWithoutFee + fee);

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssetWithFee);
        vm.stopPrank();

        // Verify: Alice gets assets minus NEW fee (200 tokens)
        uint256 newFee = getQuantizedValue(200);
        uint256 assetsToAlice = expectedAssetWithFee - newFee;

        assertEq(assetsToAlice, 0, "Number of assets sent to Alice should be 0");

        assertEq(token.balanceOf(alice), aliceBalanceBefore + assetsToAlice, "Alice should receive assets minus NEW fee");
        assertEq(token.balanceOf(feeRecipient), feeRecipientBalanceBefore + newFee, "Fee recipient should get NEW fee");
    }

    function test_flatWithdrawalFee_increasedFrom100To250Tokens_duringPendingRedeem_fulfillmentFailsWhenFeeExceedsStoredAssets(
    ) public {
        // Setup: 0 deposit fee, 100 tokens withdrawal fee
        IVariableVaultFee.AssetFeeConfig memory initialConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(100)}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(200)}),    
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(200)}),    
            feeRecipient: feeRecipient
        });
        _registerAssetWithFees(initialConfig);

        // User deposits 200 tokens
        uint256 depositAmount = getQuantizedValue(200);
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        // User initiates requestRedeem (with 100 tokens fee)
        uint256 expectedAssetsWithFee = depositVault.previewRedeem(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Update withdrawal fee to 250 tokens
        IVariableVaultFee.AssetFeeConfig memory updatedConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(250) // Updated to 250 tokens
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(350) // Updated to 350 tokens
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.FLAT,
                feeAmount: getQuantizedValue(450) // Updated to 450 tokens
            }),
            feeRecipient: feeRecipient
        });

        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(address(token), updatedConfig);
        vm.stopPrank();

        deal(address(token), address(depositVault), expectedAssetsWithFee);
        // Admin fulfills redeem - THIS SHOULD FAIL because new fee (250) > stored assets (100)
        vm.startPrank(users.admin);

        // This should revert because 250 tokens fee > 100 tokens stored assets
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InsufficientAmount.selector);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();
    }

    // ========================================= SCENARIO 2: PERCENTAGE FEE UPDATES DURING PENDING REDEEM =========================================

    function test_percentageWithdrawalFee_unchangedAt05Percent_duringPendingRedeem_usesOriginalFeeAtFulfillment()
        public
    {
        // Deploy MockVariableVaultFee with 200% max
        VariableVaultFee feeContract = new VariableVaultFee(users.admin);

        // Set mock fee contract
        vm.startPrank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(feeContract)));
        vm.stopPrank();

        // Setup: 0.1% deposit fee, 0.5% withdrawal fee
        IVariableVaultFee.AssetFeeConfig memory initialConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 1e15 // 0.1%
            }),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 5e15 // 0.5%
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 5e15 // 0.5%
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 5e15 // 0.5%
            }),
            feeRecipient: feeRecipient
        });

        vm.startPrank(users.admin);
        feeContract.registerAsset(address(token), initialConfig);
        vm.stopPrank();

        // User deposits 10,000 tokens
        uint256 depositAmount = getQuantizedValue(10000);
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        // User initiates requestRedeem
        uint256 expectedAssetsWithFee = depositVault.previewRedeem(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Fee remains unchanged (0.5%) - no update needed

        // Admin fulfills redeem
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);
        uint256 expectedFee = Math.mulDiv(expectedAssetsWithFee, 5e15, 5e15 + 1e18, Math.Rounding.Ceil);

        deal(address(token), address(depositVault), expectedAssetsWithFee);

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Verify: Should work normally with 0.5% fee
        assertEq(
            token.balanceOf(alice),
            aliceBalanceBefore + expectedAssetsWithFee - expectedFee,
            "Alice should receive assets"
        );
        assertEq(token.balanceOf(feeRecipient), feeRecipientBalanceBefore + expectedFee, "Fee recipient should get fee");
    }

    function test_percentageWithdrawalFee_increasedFrom05To1Percent_duringPendingRedeem_usesNewFeeAtFulfillment()
        public
    {
        // Deploy MockVariableVaultFee with 200% max
        VariableVaultFee feeContract = new VariableVaultFee(users.admin);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(feeContract)));
        vm.stopPrank();

        // Setup: 0.1% deposit fee, 0.5% withdrawal fee
        IVariableVaultFee.AssetFeeConfig memory initialConfig = IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 1e15 // 0.1%
            }),
            withdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 5e15 // 0.5%
            }),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 10e15 // 1%
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: 2e15 // 2%
            }),
            feeRecipient: feeRecipient
        });

        vm.startPrank(users.admin);
        feeContract.registerAsset(address(token), initialConfig);
        vm.stopPrank();

        // User deposits 10,000 tokens and requests redeem
        uint256 depositAmount = getQuantizedValue(10000);
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);
        uint256 expectedAssetsWithFee = depositVault.previewRedeem(shares);
        uint256 expectedFee = Math.mulDiv(expectedAssetsWithFee, 5e15, 5e15 + 1e18, Math.Rounding.Ceil);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Assume there are more deposits from other users
        vm.startPrank(bob);
        token.approve(address(depositVault), depositAmount * 3);
        depositVault.deposit(depositAmount, bob);
        depositVault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Update withdrawal fee to 1%
        IVariableVaultFee.AssetFeeConfig memory updatedConfig = initialConfig;
        updatedConfig.withdrawalFee.feeAmount = 1e16; // 1%

        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(address(token), updatedConfig);
        vm.stopPrank();

        // Admin fulfills redeem
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 depositVaultBalanceBefore = depositVault.balanceOf(address(depositVault));
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        vm.startPrank(users.admin);
        deal(address(token), address(depositVault), expectedAssetsWithFee);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Calculate expected amounts with NEW 1% fee
        uint256 newFee = Math.mulDiv(expectedAssetsWithFee, 1e16, 1e16 + 1e18, Math.Rounding.Ceil);
        uint256 expectedAssetsToAlice = expectedAssetsWithFee - newFee;

        assertGt(newFee, expectedFee);

        assertEq(
            depositVault.balanceOf(address(depositVault)),
            depositVaultBalanceBefore - shares,
            "Vault shares should reduce"
        ); // shares are burnt
        assertEq(
            token.balanceOf(alice),
            aliceBalanceBefore + expectedAssetsToAlice,
            "Alice should get assets minus NEW 1% fee"
        );
        assertEq(
            token.balanceOf(feeRecipient), feeRecipientBalanceBefore + newFee, "Fee recipient should get NEW 1% fee"
        );
    }

    // todo: When running cancel Redeem, there is a possibility that you could
    // specify the incorrect number of assets for the corresponding number\
    // of shares or vice-versa
    // Eg: Let's assume that a user initiates a requestRedeem for 100 shares.
    // Let's assume the asset value is 100. When cancelling the redeem, it's
    // possible for admin to call 100 shares with 50 as asset value or vice-versa

    // ========================================= PREVIEW FUNCTION TESTS =========================================

    function test_previewDeposit_WithFlatFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 assets = DEPOSIT_AMOUNT_MEDIUM;
        uint256 expectedFee = FLAT_FEE_AMOUNT;

        uint256 previewShares = depositVault.previewDeposit(assets);
        assertEq(
            previewShares,
            DEPOSIT_AMOUNT_MEDIUM - expectedFee,
            "Preview shares should match with the deposited amount - fee"
        );

        // Execute actual deposit
        vm.startPrank(alice);
        token.approve(address(depositVault), assets);
        uint256 actualShares = depositVault.deposit(assets, alice);
        vm.stopPrank();

        assertEq(actualShares, previewShares, "Actual shares should match preview");
    }

    function test_previewDeposit_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 assets = DEPOSIT_AMOUNT_MEDIUM;
        uint256 expectedFee =
            Math.mulDiv(assets, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil);

        uint256 previewShares = depositVault.previewDeposit(assets);
        assertEq(
            previewShares,
            DEPOSIT_AMOUNT_MEDIUM - expectedFee,
            "Preview shares should match with the deposited amount - fee"
        );

        vm.startPrank(alice);
        token.approve(address(depositVault), assets);
        uint256 actualShares = depositVault.deposit(assets, alice);
        vm.stopPrank();

        assertEq(actualShares, previewShares, "Actual shares should match preview with percentage fee");
    }

    function test_previewDeposit_WithZeroFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupPercentageFeeConfig(0, 0, 0, 0);
        _registerAssetWithFees(assetConfig);

        uint256 assets = DEPOSIT_AMOUNT_MEDIUM;
        uint256 previewShares = depositVault.previewDeposit(assets);
        uint256 expectedShares = depositVault.convertToShares(assets);

        assertEq(previewShares, expectedShares, "With zero fee, preview should equal convert");
    }

    function test_previewMint_WithFlatFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 shares = getQuantizedValue(1000);
        uint256 previewAssets = depositVault.previewMint(shares);

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);
        uint256 actualAssets = depositVault.mint(shares, alice);
        vm.stopPrank();

        assertEq(actualAssets, previewAssets, "Actual assets should match preview");
    }

    function test_previewMint_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 shares = getQuantizedValue(5000);
        uint256 expectedFee = Math.mulDiv(shares, PERCENTAGE_FEE_05_PERCENT, 1e18, Math.Rounding.Ceil);

        uint256 previewAssets = depositVault.previewMint(shares);
        assertEq(previewAssets, shares + expectedFee, "Preview assets should be equal to the shares + expected fee");

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);
        uint256 actualAssets = depositVault.mint(shares, alice);
        vm.stopPrank();

        assertEq(actualAssets, previewAssets, "Actual assets should match preview with percentage fee");
    }

    function test_previewWithdraw_ReturnsCorrectShares() public {
        // Note: withdraw function reverts, but preview should still work
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 assets = DEPOSIT_AMOUNT_MEDIUM;
        uint256 previewShares = depositVault.previewWithdraw(assets);

        // Verify calculation includes fee
        uint256 expectedFee = FLAT_FEE_AMOUNT;
        uint256 assetsWithFee = assets + expectedFee;
        uint256 expectedShares = depositVault.convertToShares(assetsWithFee);

        assertEq(previewShares, expectedShares, "Preview should include withdrawal fee in calculation");
    }

    function test_previewRedeem_WithFlatFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        // First deposit to get shares
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        uint256 previewAssets = depositVault.previewRedeem(shares);

        // Verify fee is deducted
        uint256 assetsBeforeFee = depositVault.convertToAssets(shares);
        uint256 expectedFee = FLAT_FEE_AMOUNT;
        uint256 expectedAssets = assetsBeforeFee - expectedFee;

        assertEq(previewAssets, expectedAssets, "Preview should deduct withdrawal fee");
    }

    function test_previewRedeem_WithPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_LARGE, alice);
        vm.stopPrank();

        uint256 previewAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 previewAssetsWithFee = depositVault.convertToAssets(shares);

        // Create redeem request to verify preview matches actual
        vm.startPrank(alice);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets,) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, previewAssetsWithFee, "Pending assets should match preview");
    }

    // ========================================= EDGE CASE TESTS =========================================

    function test_deposit_Revert_VerySmallAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 smallAmount = getQuantizedValue(1); // 1 token

        vm.startPrank(alice);
        token.approve(address(depositVault), smallAmount);

        // This should result in a revert
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InsufficientAmount.selector);
        depositVault.deposit(smallAmount, alice);
        vm.stopPrank();
    }

    function test_deposit_EdgeCase_ExactFlatFeeAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 exactFeeAmount = FLAT_FEE_AMOUNT;

        vm.startPrank(alice);
        token.approve(address(depositVault), exactFeeAmount);

        uint256 shares = depositVault.deposit(exactFeeAmount, alice);
        vm.stopPrank();

        assertEq(shares, 0, "Should get zero shares when deposit equals flat fee");
        assertEq(token.balanceOf(feeRecipient), FLAT_FEE_AMOUNT, "Fee recipient should get full amount");
    }

    function test_deposit_EdgeCase_FeeGreaterThanDepositFeeAmount() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = getQuantizedValue(10);
        uint256 exactFeeAmount = FLAT_FEE_AMOUNT;

        vm.startPrank(alice);
        token.approve(address(depositVault), exactFeeAmount);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InsufficientAmount.selector);
        uint256 shares = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(shares, 0, "Should get zero shares when deposit equals flat fee");
        assertEq(token.balanceOf(feeRecipient), 0, "Fee recipient should have 0 balance");
    }

    function test_mint_EdgeCase_MaximumPercentageFee() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 shares = getQuantizedValue(1000);
        uint256 previewAssets = depositVault.previewMint(shares);
        uint256 expectedFee = Math.mulDiv(shares, PERCENTAGE_FEE_5_PERCENT, 1e18, Math.Rounding.Ceil);

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);
        uint256 actualAssets = depositVault.mint(shares, alice);
        vm.stopPrank();

        assertEq(actualAssets, previewAssets, "Should handle maximum percentage fee correctly");

        // Verify fee was charged
        assertEq(token.balanceOf(feeRecipient), expectedFee, "Fee should be approximately 5%");
    }

    function test_requestRedeem_EdgeCase_MultipleRequests() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        // Make multiple deposits
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 shares1 = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 shares2 = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);

        // Create multiple redeem requests
        uint256 assets1 = depositVault.previewRedeem(shares1);
        uint256 assets2 = depositVault.previewRedeem(shares2);
        uint256 fee = FLAT_FEE_AMOUNT;
        uint256 cumFee = FLAT_FEE_AMOUNT * 2;

        depositVault.requestRedeem(shares1, alice, alice);
        depositVault.requestRedeem(shares2, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingShares, shares1 + shares2, "Should accumulate all pending shares");
        assertEq(pendingAssets, assets1 + assets2 + cumFee, "Should accumulate all pending assets");
    }

    function test_fulfillRedeem_EdgeCase_ExactBalance() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(shares);
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Fund vault with exact amount needed
        uint256 vaultBalance = token.balanceOf(address(depositVault));
        if (vaultBalance < expectedAssetsWithFee) {
            deal(address(token), address(depositVault), expectedAssetsWithFee - vaultBalance);
        }

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Should succeed even with exact balance
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, 0, "Should clear all pending assets");
        assertEq(pendingShares, 0, "Should clear all pending shares");
    }

    // ========================================= FEE CALCULATION CONSISTENCY TESTS =========================================

    function test_feeConsistency_DepositAndMintEquivalence() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 baseAmount = DEPOSIT_AMOUNT_MEDIUM;

        // Test deposit path
        // previewSharesFromDeposit = convertToShares(amount) - fee (fee on total)
        uint256 previewSharesFromDeposit = depositVault.previewDeposit(baseAmount);

        // Test mint path - find equivalent
        // previewAssetsForMint = convertToAssets(shares) + fee (fee on raw)
        uint256 previewAssetsForMint = depositVault.previewMint(previewSharesFromDeposit);

        // The amounts should be equal
        assertLe(previewAssetsForMint, baseAmount, "Mint and Deposit should be equivalent");
    }

    function test_feeConsistency_PreviewMatchesActual() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_MEDIUM;
        uint256 previewShares = depositVault.previewDeposit(depositAmount);
        uint256 previewAssets = depositVault.previewMint(previewShares);

        // Execute deposit
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 actualShares = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Execute mint with bob
        vm.startPrank(bob);
        token.approve(address(depositVault), previewAssets);
        uint256 actualAssets = depositVault.mint(previewShares, bob);
        vm.stopPrank();

        assertEq(actualShares, previewShares, "Deposit: actual should match preview");
        assertEq(actualAssets, previewAssets, "Mint: actual should match preview");
    }

    function test_feeConsistency_RoundTripNoProfit() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = getQuantizedValue(50_000);
        uint256 aliceTokensBalanceBefore = token.balanceOf(alice);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);

        // Deposit
        uint256 shares = depositVault.deposit(depositAmount, alice);

        // Immediately request redeem
        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Fund vault and fulfill
        uint256 expectedAssets = depositVault.previewRedeem(shares);
        deal(address(token), address(depositVault), expectedAssets);

        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssets);
        vm.stopPrank();

        uint256 finalBalance = token.balanceOf(alice);

        // Due to fees on both sides, alice should have less than initial
        assertLt(finalBalance, aliceTokensBalanceBefore, "Round trip should result in loss due to fees");
    }

    // ========================================= INTEGRATION TESTS =========================================

    function test_integration_CompleteDepositRedeemCycle() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = DEPOSIT_AMOUNT_LARGE;
        uint256 aliceInitialBalance = token.balanceOf(alice);

        // Step 1: Deposit
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Step 2: Request redeem
        vm.startPrank(alice);
        uint256 expectedAssetsWithoutFee = depositVault.previewRedeem(shares);
        uint256 expectedAssetsWithFee = depositVault.convertToAssets(shares);
        uint256 expectedFee =
            Math.mulDiv(shares, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil);
        assertEq(expectedAssetsWithFee - expectedAssetsWithoutFee, expectedFee, "Fee does not match expectation");

        depositVault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Step 3: Fund vault
        deal(address(token), address(depositVault), expectedAssetsWithFee);

        // Step 4: Fulfill redeem
        vm.startPrank(users.admin);
        depositVault.fulfillRedeem(alice, shares, expectedAssetsWithFee);
        vm.stopPrank();

        // Verify final state
        uint256 aliceFinalBalance = token.balanceOf(alice);
        uint256 feeRecipientBalance = token.balanceOf(feeRecipient);

        assertLt(aliceFinalBalance, aliceInitialBalance, "Alice should have less due to fees");
        assertGt(feeRecipientBalance, 0, "Fee recipient should have received fees");

        // Verify no pending requests
        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssets, 0, "No pending assets");
        assertEq(pendingShares, 0, "No pending shares");
    }

    function test_integration_MultiUserWithDifferentFees() public {
        // Register asset with fees
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 depositAmount = getQuantizedValue(10000);

        // Alice deposits
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 aliceShares = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Bob mints
        vm.startPrank(bob);
        uint256 bobShares = getQuantizedValue(5000);
        uint256 bobAssets = depositVault.previewMint(bobShares);
        token.approve(address(depositVault), bobAssets);
        depositVault.mint(bobShares, bob);
        vm.stopPrank();

        // Both request redeem
        vm.startPrank(alice);
        depositVault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        depositVault.requestRedeem(bobShares, bob, bob);
        vm.stopPrank();

        // Check total pending
        uint256 totalPending = depositVault.totalPendingAssets();
        (uint256 alicePending,) = depositVault.pendingRedeemRequest(alice);
        (uint256 bobPending,) = depositVault.pendingRedeemRequest(bob);

        assertEq(totalPending, alicePending + bobPending, "Total pending should equal sum of individual pending");
    }

    // ========================================= ERROR CASE TESTS =========================================

    function test_errorHandling_FeeContractNotSet() public {
        // Deploy new vault without fee contract
        vm.startPrank(users.admin);
        MultipliVault vault = new MultipliVault();
        bytes memory data =
            abi.encodeWithSelector(MultipliVault.initialize.selector, token, users.admin, "Test Vault", "TEST");

        address proxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        MultipliVault newVault = MultipliVault(payable(address(proxy)));

        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(newVault), DEPOSIT_AMOUNT_MEDIUM);

        // Should revert when trying to calculate fees
        vm.expectRevert();
        newVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    function test_errorHandling_AssetNotRegistered() public {
        // Asset is not registered in fee contract
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        // Should revert because token is not registered
        vm.expectRevert();
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    function test_errorHandling_FeeRecipientZeroAddress() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        assetConfig.feeRecipient = address(0);

        vm.startPrank(users.admin);
        vm.expectRevert(); // Should revert with InvalidAssetConfig
        feeContract.registerAsset(address(token), assetConfig);
        vm.stopPrank();
    }

    // ========================================= FUZZ TESTS =========================================

    function testFuzz_deposit_ValidAmounts(uint256 amount) public {
        amount = bound(amount, FLAT_FEE_AMOUNT + 1, getQuantizedValue(1_000_000)); // Min above flat fee, max 1M tokens

        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), amount);

        uint256 previewShares = depositVault.previewDeposit(amount);
        uint256 actualShares = depositVault.deposit(amount, alice);

        assertEq(actualShares, previewShares, "Fuzz: actual should match preview");
        vm.stopPrank();
    }

    function testFuzz_mint_ValidShares(uint256 shares) public {
        shares = bound(shares, 1e18, 100000e18); // 1 to 100k shares

        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT, PERCENTAGE_FEE_05_PERCENT);
        _registerAssetWithFees(assetConfig);

        uint256 previewAssets = depositVault.previewMint(shares);

        deal(address(token), alice, previewAssets);

        vm.startPrank(alice);
        token.approve(address(depositVault), previewAssets);

        uint256 actualAssets = depositVault.mint(shares, alice);
        assertEq(actualAssets, previewAssets, "Fuzz: mint actual should match preview");

        vm.stopPrank();
    }

    function testFuzz_requestRedeem_ValidShares(uint256 depositAmount, uint256 redeemPercentage) public {
        depositAmount = bound(depositAmount, getQuantizedValue(1_000), getQuantizedValue(100_000));
        redeemPercentage = bound(redeemPercentage, 1, 100);

        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 shares = depositVault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = (shares * redeemPercentage) / 100;
        if (sharesToRedeem > 0) {
            uint256 expectedAssets = depositVault.previewRedeem(sharesToRedeem); // returned amount does not include fee
            uint256 expectedAssetsWithFee = depositVault.convertToAssets(sharesToRedeem);
            uint256 fee = expectedAssetsWithFee - expectedAssets;

            depositVault.requestRedeem(sharesToRedeem, alice, alice);

            (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
            assertEq(pendingShares, sharesToRedeem, "Fuzz: pending shares should match requested");
            assertEq(pendingAssets, expectedAssets + fee, "Fuzz: pending assets should match preview + fee");
        }
        vm.stopPrank();
    }

    // ========================================= GAS OPTIMIZATION TESTS =========================================

    function test_gasUsage_DepositWithFees() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT);
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        uint256 gasBefore = gasleft();
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (this is more of a regression test)
        assertLt(gasUsed, 154_000, "Deposit with fees should not use excessive gas"); // 153,357
        vm.stopPrank();
    }

    function test_gasUsage_RequestRedeemWithFees() public {
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig();
        _registerAssetWithFees(assetConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);

        uint256 gasBefore = gasleft();
        depositVault.requestRedeem(shares, alice, alice);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 105000, "Request redeem should not use excessive gas"); // 103,012
        vm.stopPrank();
    }
}
