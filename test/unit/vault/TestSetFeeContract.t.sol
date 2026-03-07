// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {VaultFeeUpgradeable} from "src/base/VaultFeeUpgradeable.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestSetFeeContract is BaseTest {
    // Fee contracts
    VariableVaultFee internal primaryFeeContract;
    VariableVaultFee internal secondaryFeeContract;
    VariableVaultFee internal tertiaryFeeContract;

    // Fee recipients
    address internal primaryFeeRecipient;
    address internal secondaryFeeRecipient;
    address internal tertiaryFeeRecipient;

    // Test users
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal unauthorizedUser;

    // Constants for fee testing
    uint256 internal FLAT_FEE_AMOUNT;
    uint256 internal constant PERCENTAGE_FEE_1_PERCENT = 1e16; // 1%
    uint256 internal constant PERCENTAGE_FEE_25_PERCENT = 25e15; // 2.5%
    uint256 internal constant PERCENTAGE_FEE_5_PERCENT = 5e16; // 5%

    // Test amounts
    uint256 internal DEPOSIT_AMOUNT_SMALL;
    uint256 internal DEPOSIT_AMOUNT_MEDIUM;
    uint256 internal DEPOSIT_AMOUNT_LARGE;

    function setUp() public override {
        BaseTest.setUp();

        FLAT_FEE_AMOUNT = getQuantizedValue(100); 

        DEPOSIT_AMOUNT_SMALL = getQuantizedValue(1000);
        DEPOSIT_AMOUNT_MEDIUM = getQuantizedValue(10000); 
        DEPOSIT_AMOUNT_LARGE = getQuantizedValue(100000); 

        // Set up test users
        alice = users.alice;
        bob = users.bob;
        charlie = makeAddr("Charlie");
        unauthorizedUser = makeAddr("UnauthorizedUser");

        // Set up fee recipients
        primaryFeeRecipient = makeAddr("PrimaryFeeRecipient");
        secondaryFeeRecipient = makeAddr("SecondaryFeeRecipient");
        tertiaryFeeRecipient = makeAddr("TertiaryFeeRecipient");

        // Deploy multiple fee contracts
        primaryFeeContract = new VariableVaultFee(users.admin);
        secondaryFeeContract = new VariableVaultFee(users.admin);
        tertiaryFeeContract = new VariableVaultFee(users.admin);

        // Set primary fee contract in vault
        vm.startPrank(users.admin);
        depositVault.setFeeContract(primaryFeeContract);
        vm.stopPrank();

        // Fund test users with tokens
        _fundUsers();
    }

    function _fundUsers() internal {
        vm.startPrank(users.admin);
        deal(address(token), alice, getQuantizedValue(1_000_000)); // 1M tokens
        deal(address(token), bob, getQuantizedValue(1_000_000)); // 1M tokens
        deal(address(token), charlie, getQuantizedValue(1_000_000)); // 1M tokens
        vm.stopPrank();
    }

    function _setupFlatFeeConfig(address feeRecipient)
        internal
        view
        returns (IVariableVaultFee.AssetFeeConfig memory)
    {
        return IVariableVaultFee.AssetFeeConfig({
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: FLAT_FEE_AMOUNT}),
            feeRecipient: feeRecipient
        });
    }

    function _setupPercentageFeeConfig(uint256 depositFeePercent, uint256 withdrawalFeePercent, address feeRecipient)
        internal
        view
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
                feeAmount: withdrawalFeePercent
            }),
            flashRedeemFee: IVariableVaultFee.FeeConfig({
                feeType: IVariableVaultFee.FeeType.PERCENTAGE,
                feeAmount: withdrawalFeePercent
            }),
            feeRecipient: feeRecipient
        });
    }

    function _registerAssetWithFees(VariableVaultFee feeContractToUse, IVariableVaultFee.AssetFeeConfig memory assetConfig)
        internal
    {
        vm.startPrank(users.admin);
        feeContractToUse.registerAsset(address(token), assetConfig);
        vm.stopPrank();
    }

    // ========================================= BASIC SET FEE CONTRACT TESTS =========================================

    function test_setFeeContract_Success_InitialSetup() public {
        address currentFeeContract = address(depositVault.feeContract());
        assertEq(currentFeeContract, address(primaryFeeContract), "Fee contract should be set correctly in setup");
    }

    function test_setFeeContract_Success_UpdateToNewContract() public {
        vm.startPrank(users.admin);

        // Expect FeeContractUpdated event
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(primaryFeeContract), address(secondaryFeeContract)
        );

        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        assertEq(address(depositVault.feeContract()), address(secondaryFeeContract), "Fee contract should be updated");
    }

    function test_setFeeContract_Success_SetToZeroAddress() public {
        vm.startPrank(users.admin);

        // Expect FeeContractUpdated event
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(users.admin, address(primaryFeeContract), address(0));

        depositVault.setFeeContract(IVariableVaultFee(address(0)));
        vm.stopPrank();

        assertEq(address(depositVault.feeContract()), address(0), "Fee contract should be set to zero");
    }

    function test_setFeeContract_Success_UpdateMultipleTimes() public {
        vm.startPrank(users.admin);

        // First update
        depositVault.setFeeContract(secondaryFeeContract);
        assertEq(
            address(depositVault.feeContract()), address(secondaryFeeContract), "Should update to secondary contract"
        );

        // Second update
        depositVault.setFeeContract(tertiaryFeeContract);
        assertEq(
            address(depositVault.feeContract()), address(tertiaryFeeContract), "Should update to tertiary contract"
        );

        // Back to original
        depositVault.setFeeContract(primaryFeeContract);
        assertEq(address(depositVault.feeContract()), address(primaryFeeContract), "Should update back to primary");

        // To zero
        depositVault.setFeeContract(IVariableVaultFee(address(0)));
        assertEq(address(depositVault.feeContract()), address(0), "Should update to zero address");

        // Back to non-zero
        depositVault.setFeeContract(primaryFeeContract);
        assertEq(
            address(depositVault.feeContract()), address(primaryFeeContract), "Should update back to primary from zero"
        );

        vm.stopPrank();
    }

    function test_setFeeContract_Success_SetSameContract() public {
        vm.startPrank(users.admin);

        // Set to the same contract (should work fine)
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(primaryFeeContract), address(primaryFeeContract)
        );

        depositVault.setFeeContract(primaryFeeContract);

        assertEq(address(depositVault.feeContract()), address(primaryFeeContract), "Should remain the same contract");
        vm.stopPrank();
    }

    // ========================================= ACCESS CONTROL TESTS =========================================

    function test_setFeeContract_RevertsWhen_UnauthorizedUser() public {
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();
    }

    function test_setFeeContract_RevertsWhen_Alice() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();
    }

    function test_setFeeContract_RevertsWhen_Bob() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();
    }

    function test_setFeeContract_RevertsWhen_Charlie() public {
        vm.startPrank(charlie);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();
    }

    function test_setFeeContract_Success_AdminOnly() public {
        // Verify admin can set
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        assertEq(address(depositVault.feeContract()), address(secondaryFeeContract), "Admin should be able to set");
        vm.stopPrank();
    }

    // ========================================= FEE CALCULATION BEHAVIOR TESTS =========================================

    function test_setFeeContract_NewContractUsedForCalculations_FlatToPercentage() public {
        // Setup initial state with flat fee
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        // Test initial deposit with flat fee
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 initialShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        uint256 initialFeeRecipientBalance = token.balanceOf(primaryFeeRecipient);
        assertEq(initialFeeRecipientBalance, FLAT_FEE_AMOUNT, "Initial flat fee should be charged");

        // Deploy and configure new fee contract with percentage fee
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        // Update fee contract
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Verify fee recipient changed
        assertEq(depositVault.getFeeRecipient(), secondaryFeeRecipient, "Fee recipient should update");

        // Test deposit with new percentage fee contract
        vm.startPrank(bob);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        uint256 expectedPercentageFee = Math.mulDiv(
            DEPOSIT_AMOUNT_MEDIUM, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil
        );
        uint256 secondaryFeeRecipientBalanceBefore = token.balanceOf(secondaryFeeRecipient);

        uint256 newShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, bob);
        vm.stopPrank();

        // Verify new fee calculation
        uint256 secondaryFeeRecipientBalanceAfter = token.balanceOf(secondaryFeeRecipient);
        uint256 actualFeeCharged = secondaryFeeRecipientBalanceAfter - secondaryFeeRecipientBalanceBefore;

        assertEq(actualFeeCharged, expectedPercentageFee, "Should charge percentage fee, not flat fee");
        assertGt(newShares, initialShares, "Should get more shares with percentage fee vs flat fee for same deposit");

        // Verify old fee recipient didn't receive anything
        assertEq(
            token.balanceOf(primaryFeeRecipient), FLAT_FEE_AMOUNT, "Primary fee recipient should not receive new fees"
        );
    }

    function test_setFeeContract_NewContractUsedForCalculations_PercentageToFlat() public {
        // Setup initial state with percentage fee
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_25_PERCENT, PERCENTAGE_FEE_25_PERCENT, primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, percentageConfig);

        // Test initial deposit with percentage fee
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 initialShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        uint256 expectedInitialFee = Math.mulDiv(
            DEPOSIT_AMOUNT_MEDIUM, PERCENTAGE_FEE_25_PERCENT, PERCENTAGE_FEE_25_PERCENT + 1e18, Math.Rounding.Ceil
        );
        assertEq(token.balanceOf(primaryFeeRecipient), expectedInitialFee, "Initial percentage fee should be charged");

        // Setup new contract with flat fee
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, flatConfig);

        // Update fee contract
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Test deposit with new flat fee contract
        vm.startPrank(bob);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        uint256 secondaryFeeRecipientBalanceBefore = token.balanceOf(secondaryFeeRecipient);
        uint256 newShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, bob);
        vm.stopPrank();

        // Verify flat fee was charged
        uint256 actualFeeCharged = token.balanceOf(secondaryFeeRecipient) - secondaryFeeRecipientBalanceBefore;
        assertEq(actualFeeCharged, FLAT_FEE_AMOUNT, "Should charge flat fee, not percentage fee");
        assertGt(newShares, initialShares, "Should get more shares with flat fee vs 2.5% percentage fee");
    }

    function test_setFeeContract_NewContractUsedForCalculations_DifferentPercentages() public {
        // Setup initial state with 1% fee
        IVariableVaultFee.AssetFeeConfig memory lowPercentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, lowPercentageConfig);

        // Test deposit with 1% fee
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 initialShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        uint256 initialFee = Math.mulDiv(
            DEPOSIT_AMOUNT_MEDIUM, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil
        );
        assertEq(token.balanceOf(primaryFeeRecipient), initialFee, "Initial 1% fee should be charged");

        // Setup new contract with 5% fee
        IVariableVaultFee.AssetFeeConfig memory highPercentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, highPercentageConfig);

        // Update fee contract
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Test deposit with 5% fee
        vm.startPrank(bob);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 newShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, bob);
        vm.stopPrank();

        uint256 expectedHighFee = Math.mulDiv(
            DEPOSIT_AMOUNT_MEDIUM, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT + 1e18, Math.Rounding.Ceil
        );

        assertEq(token.balanceOf(secondaryFeeRecipient), expectedHighFee, "Should charge 5% fee");
        assertLt(newShares, initialShares, "Should get fewer shares with 5% fee vs 1% fee");
    }

    function test_setFeeContract_NewContractUsedForRedeemCalculations() public {
        // Setup with flat fee contract
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        // Alice deposits with flat fee
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 aliceShares = depositVault.deposit(DEPOSIT_AMOUNT_LARGE, alice);
        vm.stopPrank();

        // Switch to percentage fee contract
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Test redeem preview with new fee contract
        uint256 redeemPreview = depositVault.previewRedeem(aliceShares);

        // Create redeem request
        vm.startPrank(alice);
        depositVault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);

        uint256 expectedFee =
            Math.mulDiv(aliceShares, PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT + 1e18, Math.Rounding.Ceil);

        // The pending assets should match the preview, which uses the new fee contract
        assertEq(pendingAssets, redeemPreview + expectedFee, "Redeem should use new fee contract for calculations");
        assertEq(pendingShares, aliceShares, "All shares should be pending");
    }

    // ========================================= PREVIEW FUNCTION CONSISTENCY TESTS =========================================

    function test_setFeeContract_PreviewFunctionsUpdateImmediately() public {
        // Setup flat fee
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        uint256 testAmount = DEPOSIT_AMOUNT_MEDIUM;
        uint256 previewBeforeUpdate = depositVault.previewDeposit(testAmount);

        // Switch to percentage fee
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        uint256 previewAfterUpdate = depositVault.previewDeposit(testAmount);

        // Preview should be different with new fee structure
        assertNotEq(previewBeforeUpdate, previewAfterUpdate, "Preview should change with new fee contract");

        // Verify actual deposit matches new preview
        vm.startPrank(alice);
        token.approve(address(depositVault), testAmount);
        uint256 actualShares = depositVault.deposit(testAmount, alice);
        vm.stopPrank();

        assertEq(actualShares, previewAfterUpdate, "Actual deposit should match updated preview");
    }

    function test_setFeeContract_AllPreviewFunctionsUpdate() public {
        // Setup initial state
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        // Capture initial previews
        uint256 depositPreviewBefore = depositVault.previewDeposit(DEPOSIT_AMOUNT_MEDIUM);
        uint256 mintPreviewBefore = depositVault.previewMint(1000e18);
        uint256 withdrawPreviewBefore = depositVault.previewWithdraw(DEPOSIT_AMOUNT_MEDIUM);

        // Do a deposit to get shares for redeem preview
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        uint256 redeemPreviewBefore = depositVault.previewRedeem(shares);

        // Switch fee contract
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_25_PERCENT, PERCENTAGE_FEE_25_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Capture updated previews
        uint256 depositPreviewAfter = depositVault.previewDeposit(DEPOSIT_AMOUNT_MEDIUM);
        uint256 mintPreviewAfter = depositVault.previewMint(1000e18);
        uint256 withdrawPreviewAfter = depositVault.previewWithdraw(DEPOSIT_AMOUNT_MEDIUM);
        uint256 redeemPreviewAfter = depositVault.previewRedeem(shares);

        // All previews should be different
        assertNotEq(depositPreviewBefore, depositPreviewAfter, "Deposit preview should change");
        assertNotEq(mintPreviewBefore, mintPreviewAfter, "Mint preview should change");
        assertNotEq(withdrawPreviewBefore, withdrawPreviewAfter, "Withdraw preview should change");
        assertNotEq(redeemPreviewBefore, redeemPreviewAfter, "Redeem preview should change");
    }

    // ========================================= EDGE CASE TESTS =========================================

    function test_setFeeContract_OperationsFailWhenZeroAddressSet() public {
        // Set fee contract to zero
        vm.startPrank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(0)));
        vm.stopPrank();

        // Deposits should fail
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        vm.expectRevert(); // Should revert with ConfiguredIncorrectly
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    function test_setFeeContract_CanRecoverFromZeroAddress() public {
        // Set to zero
        vm.startPrank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(0)));
        vm.stopPrank();

        // Operations should fail
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        vm.expectRevert();
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Set back to valid contract
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, assetConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(primaryFeeContract);
        vm.stopPrank();

        // Operations should work again
        vm.startPrank(alice);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should work after setting valid fee contract");
    }

    function test_setFeeContract_NewContractWithoutAssetRegistration() public {
        // Switch to a fee contract that doesn't have token registered
        VariableVaultFee unregisteredFeeContract = new VariableVaultFee(users.admin);
        // Note: Not registering token in this contract

        vm.startPrank(users.admin);
        depositVault.setFeeContract(unregisteredFeeContract);
        vm.stopPrank();

        // Operations should fail
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);

        vm.expectRevert(); // Should revert because token is not registered
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();
    }

    // ========================================= INTEGRATION TESTS =========================================

    function test_setFeeContract_MultipleUsersBeforeAndAfterChange() public {
        // Setup initial fee contract
        IVariableVaultFee.AssetFeeConfig memory lowFeeConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, lowFeeConfig);

        // Alice and Bob deposit with low fee
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 aliceShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 bobShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, bob);
        vm.stopPrank();

        // Change to high fee contract
        IVariableVaultFee.AssetFeeConfig memory highFeeConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, highFeeConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Charlie deposits with high fee
        vm.startPrank(charlie);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 charlieShares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, charlie);
        vm.stopPrank();

        // Charlie should get fewer shares due to higher fee
        assertLt(charlieShares, aliceShares, "Charlie should get fewer shares with higher fee");
        assertLt(charlieShares, bobShares, "Charlie should get fewer shares with higher fee");

        // Verify fee recipients
        assertGt(token.balanceOf(primaryFeeRecipient), 0, "Primary fee recipient should have received fees");
        assertGt(token.balanceOf(secondaryFeeRecipient), 0, "Secondary fee recipient should have received fees");

        // Test redemptions use current fee contract
        vm.startPrank(alice);
        uint256 aliceRedeemPreview = depositVault.previewRedeem(aliceShares);
        depositVault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        uint256 expectedFee =
            Math.mulDiv(aliceShares, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT + 1e18, Math.Rounding.Ceil);

        (uint256 alicePendingAssets,) = depositVault.pendingRedeemRequest(alice);
        assertEq(
            alicePendingAssets,
            aliceRedeemPreview + expectedFee,
            "Alice's redeem should use current (high) fee structure"
        );
    }

    function test_setFeeContract_CompleteWorkflowWithFeeContractChanges() public {
        // Phase 1: Flat fee contract
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 shares1 = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Phase 2: Switch to percentage fee
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares2 = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Phase 3: Switch to different percentage fee
        IVariableVaultFee.AssetFeeConfig memory highPercentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, tertiaryFeeRecipient);
        _registerAssetWithFees(tertiaryFeeContract, highPercentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(tertiaryFeeContract);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares3 = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        // Verify share amounts reflect fee changes
        assertGt(shares2, shares1, "Should get more shares with 1% vs flat fee");
        assertGt(shares2, shares3, "Should get more shares with 1% vs 5% fee");

        // Test redeem with current fee structure (5%)
        uint256 totalShares = shares1 + shares2 + shares3;
        vm.startPrank(alice);
        depositVault.requestRedeem(totalShares, alice, alice);
        vm.stopPrank();

        (uint256 pendingAssets, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingShares, totalShares, "All shares should be pending");
        assertEq(pendingShares, depositVault.totalSupply(), "All shares should be pending");

        uint256 expectedFee =
            Math.mulDiv(totalShares, PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT + 1e18, Math.Rounding.Ceil);

        uint256 expectedAssetsWithCurrentFee = depositVault.previewRedeem(totalShares);
        assertEq(
            pendingAssets - expectedFee, expectedAssetsWithCurrentFee, "Should use current fee structure for redeem"
        );

        // Verify all fee recipients received appropriate fees
        assertEq(token.balanceOf(primaryFeeRecipient), FLAT_FEE_AMOUNT, "Primary should have flat fee");
        assertGt(token.balanceOf(secondaryFeeRecipient), 0, "Secondary should have 1% fee");
        assertGt(token.balanceOf(tertiaryFeeRecipient), 0, "Tertiary should have 5% fee");
    }

    // ========================================= EVENT TESTING =========================================

    function test_setFeeContract_EmitsCorrectEvents() public {
        // Test event for updating to new contract
        vm.startPrank(users.admin);

        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(primaryFeeContract), address(secondaryFeeContract)
        );
        depositVault.setFeeContract(secondaryFeeContract);

        // Test event for updating to zero
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(users.admin, address(secondaryFeeContract), address(0));
        depositVault.setFeeContract(IVariableVaultFee(address(0)));

        // Test event for updating back from zero
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(users.admin, address(0), address(tertiaryFeeContract));
        depositVault.setFeeContract(tertiaryFeeContract);

        vm.stopPrank();
    }

    function test_setFeeContract_EventsWithMultipleUpdates() public {
        vm.startPrank(users.admin);

        // Multiple rapid updates should emit multiple events
        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(primaryFeeContract), address(secondaryFeeContract)
        );
        depositVault.setFeeContract(secondaryFeeContract);

        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(secondaryFeeContract), address(tertiaryFeeContract)
        );
        depositVault.setFeeContract(tertiaryFeeContract);

        vm.expectEmit(true, true, true, true);
        emit VaultFeeUpgradeable.FeeContractUpdated(
            users.admin, address(tertiaryFeeContract), address(primaryFeeContract)
        );
        depositVault.setFeeContract(primaryFeeContract);

        vm.stopPrank();
    }

    // ========================================= GET FEE RECIPIENT TESTS =========================================

    function test_getFeeRecipient_UpdatesWithFeeContract() public {
        // Setup different fee contracts with different recipients
        IVariableVaultFee.AssetFeeConfig memory assetConfig1 = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, assetConfig1);

        IVariableVaultFee.AssetFeeConfig memory assetConfig2 =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, assetConfig2);

        // Initially should be primary
        assertEq(depositVault.getFeeRecipient(), primaryFeeRecipient, "Should start with primary fee recipient");

        // Switch to secondary
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        assertEq(depositVault.getFeeRecipient(), secondaryFeeRecipient, "Should update to secondary fee recipient");

        // Switch back
        vm.startPrank(users.admin);
        depositVault.setFeeContract(primaryFeeContract);
        vm.stopPrank();

        assertEq(depositVault.getFeeRecipient(), primaryFeeRecipient, "Should revert to primary fee recipient");
    }

    function test_getFeeRecipient_RevertsWhenFeeContractZero() public {
        vm.startPrank(users.admin);
        depositVault.setFeeContract(IVariableVaultFee(address(0)));
        vm.stopPrank();

        vm.expectRevert(); // Should revert when trying to get fee recipient from zero address
        depositVault.getFeeRecipient();
    }

    // ========================================= FUZZ TESTS =========================================

    function testFuzz_setFeeContract_MultipleUpdates(uint8 numUpdates) public {
        numUpdates = uint8(bound(numUpdates, 1, 20)); // Test 1-20 updates

        VariableVaultFee[] memory feeContracts = new VariableVaultFee[](3);
        feeContracts[0] = primaryFeeContract;
        feeContracts[1] = secondaryFeeContract;
        feeContracts[2] = tertiaryFeeContract;

        vm.startPrank(users.admin);

        for (uint8 i = 0; i < numUpdates; i++) {
            uint8 contractIndex = i % 3;
            depositVault.setFeeContract(feeContracts[contractIndex]);

            // Verify the contract was set
            assertEq(
                address(depositVault.feeContract()),
                address(feeContracts[contractIndex]),
                "Fee contract should be set correctly"
            );
        }

        vm.stopPrank();
    }

    function testFuzz_setFeeContract_FeeCalculationConsistency(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, getQuantizedValue(1000), getQuantizedValue(100_000)); // 1k to 100k tokens

        // Setup two different fee contracts
        IVariableVaultFee.AssetFeeConfig memory assetConfig1 =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, assetConfig1);

        IVariableVaultFee.AssetFeeConfig memory assetConfig2 =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_25_PERCENT, PERCENTAGE_FEE_25_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, assetConfig2);

        // Test with first contract
        uint256 preview1 = depositVault.previewDeposit(depositAmount);

        // Switch to second contract
        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        uint256 preview2 = depositVault.previewDeposit(depositAmount);

        // Preview should be different (lower with higher fee)
        assertLt(preview2, preview1, "Higher fee should result in fewer shares");

        // Actual deposit should match current preview
        vm.startPrank(alice);
        token.approve(address(depositVault), depositAmount);
        uint256 actualShares = depositVault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(actualShares, preview2, "Actual should match current preview");
    }

    // ========================================= COMPLEX SCENARIO TESTS =========================================

    function test_setFeeContract_PendingRedeemsWithFeeContractChange() public {
        // Setup initial fee contract
        IVariableVaultFee.AssetFeeConfig memory flatConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, flatConfig);

        // Alice deposits and creates redeem request
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_LARGE);
        uint256 aliceShares = depositVault.deposit(DEPOSIT_AMOUNT_LARGE, alice);
        uint256 expectedFee = FLAT_FEE_AMOUNT;
        uint256 initialRedeemPreview = depositVault.previewRedeem(aliceShares);
        depositVault.requestRedeem(aliceShares, alice, alice);
        vm.stopPrank();

        (uint256 initialPendingAssets,) = depositVault.pendingRedeemRequest(alice);
        assertEq(initialPendingAssets, initialRedeemPreview + expectedFee, "Initial pending should match preview + fee");

        // Change fee contract (should not affect existing pending requests)
        IVariableVaultFee.AssetFeeConfig memory percentageConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_5_PERCENT, PERCENTAGE_FEE_5_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, percentageConfig);

        vm.startPrank(users.admin);
        depositVault.setFeeContract(secondaryFeeContract);
        vm.stopPrank();

        // Existing pending request should be unchanged
        (uint256 pendingAssetsAfterChange, uint256 pendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(pendingAssetsAfterChange, initialPendingAssets, "Existing pending should not change");
        assertEq(pendingShares, aliceShares, "Pending shares should not change");

        // But new preview should be different
        uint256 newRedeemPreview = depositVault.previewRedeem(aliceShares);
        assertNotEq(newRedeemPreview, initialRedeemPreview, "New preview should be different");

        // Fulfill the original request
        vm.startPrank(users.admin);
        deal(address(token), address(depositVault), initialPendingAssets);
        depositVault.fulfillRedeem(alice, aliceShares, initialPendingAssets);
        vm.stopPrank();

        // Should succeed with original calculation
        (uint256 finalPendingAssets, uint256 finalPendingShares) = depositVault.pendingRedeemRequest(alice);
        assertEq(finalPendingAssets, 0, "Should clear pending assets");
        assertEq(finalPendingShares, 0, "Should clear pending shares");
    }

    function test_setFeeContract_InteractionWithVaultPauseUnpause() public {
        // Setup fee contract
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, assetConfig);

        // Pause vault
        vm.startPrank(users.admin);
        depositVault.pause();

        // Should still be able to change fee contract while paused
        depositVault.setFeeContract(secondaryFeeContract);
        assertEq(
            address(depositVault.feeContract()),
            address(secondaryFeeContract),
            "Should update fee contract while paused"
        );

        // Unpause
        depositVault.unpause();
        vm.stopPrank();

        // Setup the new fee contract
        IVariableVaultFee.AssetFeeConfig memory newConfig =
            _setupPercentageFeeConfig(PERCENTAGE_FEE_1_PERCENT, PERCENTAGE_FEE_1_PERCENT, secondaryFeeRecipient);
        _registerAssetWithFees(secondaryFeeContract, newConfig);

        // Operations should work with new fee contract
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should work with new fee contract after unpause");
        assertGt(token.balanceOf(secondaryFeeRecipient), 0, "New fee recipient should receive fees");
    }

    // ========================================= STATE VERIFICATION TESTS =========================================

    function test_setFeeContract_StateConsistencyAfterMultipleChanges() public {
        address[] memory feeRecipients = new address[](3);
        feeRecipients[0] = primaryFeeRecipient;
        feeRecipients[1] = secondaryFeeRecipient;
        feeRecipients[2] = tertiaryFeeRecipient;

        VariableVaultFee[] memory contracts = new VariableVaultFee[](3);
        contracts[0] = primaryFeeContract;
        contracts[1] = secondaryFeeContract;
        contracts[2] = tertiaryFeeContract;

        // Setup all contracts
        for (uint256 i = 0; i < 3; i++) {
            IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupPercentageFeeConfig(
                PERCENTAGE_FEE_1_PERCENT + (i * PERCENTAGE_FEE_1_PERCENT), // 1%, 2%, 3%
                PERCENTAGE_FEE_1_PERCENT + (i * PERCENTAGE_FEE_1_PERCENT),
                feeRecipients[i]
            );
            _registerAssetWithFees(contracts[i], assetConfig);
        }

        vm.startPrank(users.admin);

        // Cycle through contracts multiple times
        for (uint256 cycle = 0; cycle < 3; cycle++) {
            for (uint256 i = 0; i < 3; i++) {
                depositVault.setFeeContract(contracts[i]);

                // Verify state consistency
                assertEq(address(depositVault.feeContract()), address(contracts[i]), "Contract should be set correctly");
                assertEq(depositVault.getFeeRecipient(), feeRecipients[i], "Fee recipient should match");

                // Test a small operation to ensure it works
                uint256 preview = depositVault.previewDeposit(getQuantizedValue(1000));
                assertGt(preview, 0, "Preview should work with current fee contract");
            }
        }

        vm.stopPrank();
    }

    function test_setFeeContract_NoMemoryLeaksOrStateCorruption() public {
        // This test ensures that rapid fee contract changes don't cause state issues
        vm.startPrank(users.admin);

        // Rapid changes between contracts and zero
        for (uint256 i = 0; i < 10; i++) {
            depositVault.setFeeContract(primaryFeeContract);
            depositVault.setFeeContract(IVariableVaultFee(address(0)));
            depositVault.setFeeContract(secondaryFeeContract);
            depositVault.setFeeContract(tertiaryFeeContract);
        }

        // Set to a valid contract for final test
        depositVault.setFeeContract(primaryFeeContract);
        vm.stopPrank();

        // Setup the contract
        IVariableVaultFee.AssetFeeConfig memory assetConfig = _setupFlatFeeConfig(primaryFeeRecipient);
        _registerAssetWithFees(primaryFeeContract, assetConfig);

        // Should still work normally
        vm.startPrank(alice);
        token.approve(address(depositVault), DEPOSIT_AMOUNT_MEDIUM);
        uint256 shares = depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should work normally after rapid changes");
        assertEq(address(depositVault.feeContract()), address(primaryFeeContract), "Should have correct final contract");
    }
}
