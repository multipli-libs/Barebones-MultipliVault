// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import { BaseTest } from "test/unit/vault/Base.t.sol";
import { VaultFundManager } from "src/managers/VaultFundManager.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MockOperator, MockMaliciousOperator } from "test/mocks/MockOperator.sol";
import { MockAuthority } from "test/mocks/MockAuthority.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVariableVaultFee } from "src/interfaces/IVariableVaultFee.sol";
import { MultipliVault } from "src/vault/MultipliVault.sol";
import { ZeroFeeRecipient } from "test/mocks/ZeroFeeRecipient.sol";
import { IMultipliVault } from "src/interfaces/IMultipliVault.sol";
import { IMultipliVaultCallee } from "src/interfaces/IMultipliVaultCallee.sol";

import { Errors } from "src/libraries/Errors.sol";

contract SharePriceConsistencyOperator is IMultipliVaultCallee {
    error SharePriceConsistencyOperator__SharesMismatch();
    error SharePriceConsistencyOperator__AssetsMismatch();
    error SharePriceConsistencyOperator__TransferFailed();

    MultipliVault public vault;
    IERC20 public asset;
    uint256 private expectedShares;
    uint256 private expectedAssetsWithFee;
    bool public consistencyVerified;

    function setVault(MultipliVault _vault, address _asset) external {
        vault = _vault;
        asset = IERC20(_asset);
    }

    function setExpectedValues(uint256 _shares, uint256 _assetsWithFee) external {
        expectedShares = _shares;
        expectedAssetsWithFee = _assetsWithFee;
    }

    function onRedemptionFlashLoan(
        address,
        address vaultAddress,
        address,
        uint256 shares,
        uint256,
        bytes calldata
    ) external override {
        if (shares != expectedShares) {
            revert SharePriceConsistencyOperator__SharesMismatch();
        }

        // Verify convertToAssets remains consistent during callback
        uint256 currentAssetsWithFee = vault.convertToAssets(shares);

        if (currentAssetsWithFee != expectedAssetsWithFee) {
            revert SharePriceConsistencyOperator__AssetsMismatch();
        }

        // Transfer vault shares back to complete the flash loan
        if (!IERC20(address(vault)).transfer(vaultAddress, shares)) {
            revert SharePriceConsistencyOperator__TransferFailed();
        }
        consistencyVerified = true;
    }
}


// todo: should be moved to `test/managers/`
contract TestFlashRedeem is BaseTest {
    address operatorOwner;
    uint256 operatorOwnerKey;

    VaultFundManager fundManager;
    MockOperator operator;

    uint256 INITIAL_OPERATOR_DEPOSIT_AMOUNT;

    function setUp() public override {
        BaseTest.setUp();

        INITIAL_OPERATOR_DEPOSIT_AMOUNT = getQuantizedValue(100);
        vm.startPrank(users.admin);
        
        // setup operatorOwner
        (operatorOwner, operatorOwnerKey) = makeAddrAndKey("operatorOwner");
        deal(operatorOwner, 10e18); // add eth balance
        deal(address(token), operatorOwner, getQuantizedValue(100_000)); // add 100K token balance
        vm.label({ account: operatorOwner, newLabel: "operatorOwner" });

        // setup Operator contract
        operator = new MockOperator();
        deal(address(operator), 10e18); // add eth balance
        deal(address(token), address(operator), getQuantizedValue(1_000_000)); // add 1M token balance
        operator.setVault(depositVault);
        operator.mint(INITIAL_OPERATOR_DEPOSIT_AMOUNT);
        vm.label({ account: address(operator), newLabel: "operatorContract" });

        // move assets and update underlying asset balance
        MockAuthority(address(authority)).setRoleCapability(
            ADMIN_ROLE, address(depositVault), depositVault.onUnderlyingBalanceUpdate.selector, true
        ); // set permission to call `onUnderlyingBalanceUpdate`
        moveAssetsFromVault(INITIAL_OPERATOR_DEPOSIT_AMOUNT);
        updateUnderlyingBalance(INITIAL_OPERATOR_DEPOSIT_AMOUNT);

        // `updateUnderlyingBalance` and `moveAssetsFromVault` reset the pranked user
        vm.startPrank(users.admin);

        // deploy fund manager
        fundManager = new VaultFundManager(payable(address(depositVault)));
        deal(address(token), address(fundManager), getQuantizedValue(1_000_000)); // ensure fund manager has 1M tokens

        // assign permission to admin to whitelist operators
        MockAuthority(address(authority)).setRoleCapability(
            ADMIN_ROLE, address(fundManager), fundManager.updateUserOperatorWhitelist.selector, true
        );

        // white list operator to call VaultFundManager.flashRedeem on `operator` contract
        address target = address(fundManager);
        bytes memory data = abi.encodeWithSelector(
            fundManager.updateUserOperatorWhitelist.selector, operatorOwner, address(operator), true
        );
        depositVault.manage(target, data, 0);

        // assign permission to Vault Fund Manager contract to call MultipliVault.flashRedeem and MultipliVault.onUnderlyingBalanceUpdate
        MockAuthority(address(authority)).setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE,
            address(depositVault),
            depositVault.onUnderlyingBalanceUpdate.selector,
            true
        );
        MockAuthority(address(authority)).setRoleCapability(
            FUND_MANAGER_CONTRACT_ROLE,
            address(depositVault),
            depositVault.flashRedeem.selector,
            true
        );
        MockAuthority(address(authority)).setUserRole(
            address(fundManager), FUND_MANAGER_CONTRACT_ROLE, true
        );

        vm.stopPrank();

        vm.roll(block.number + 1);
    }

    function _calculatePercentageChange(
        uint256 oldPrice,
        uint256 newPrice
    )
        private
        pure
        returns (uint256)
    {
        if (oldPrice == 0) {
            return 0;
        }

        uint256 diff = newPrice > oldPrice ? newPrice - oldPrice : oldPrice - newPrice;

        // Use Math.mulDiv for safe multiplication & division with rounding
        return Math.mulDiv(diff, DENOMINATOR, oldPrice, Math.Rounding.Ceil);
    }

    modifier mintAssetForOtherUsers() {
        uint256 aliceDepositAmount = getQuantizedValue(100);
        // ensure other users also mint, this does not affect the flow
        vm.startPrank(users.alice);
        depositVault.mint(aliceDepositAmount, users.alice);
        vm.stopPrank();
        _;
    }

    function test_flashRedeem_Success_OnPartialAmount() public {
        uint256 aggUnderlyingBalance = depositVault.aggregatedUnderlyingBalances();
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 operatorBalanceBefore = token.balanceOf(address(operator));
        uint256 fundManagerContractBalanceBefore = token.balanceOf(address(fundManager));

        address feeRecipient = depositVault.getFeeRecipient();
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        uint256 sharesToRedeem = depositVault.balanceOf(address(operator)) / 2;
        assertEq(sharesToRedeem, INITIAL_OPERATOR_DEPOSIT_AMOUNT / 2);

        // sanity check to ensure the shares
        assertEq(sharesToRedeem, getQuantizedValue(50), "Incorrect ExpectedShares");

        uint256 assetsWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 expectedFee = Math.mulDiv(assetsWithFee, 1e15, 1e15 + 1e18, Math.Rounding.Ceil);
        uint256 assetsWithoutFee = assetsWithFee - expectedFee;

        assertEq(assetsWithFee, getQuantizedValue(50), "assetsWithFee not equal expectations");
        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), sharesToRedeem, "");
        vm.stopPrank();

        // verify aggregated underlying balance was updated correctly
        assertEq(aggUnderlyingBalance - assetsWithFee, depositVault.aggregatedUnderlyingBalances());

        // verify total supply has decreased by `sharesToRedeem`
        assertEq(
            totalSupplyBefore - sharesToRedeem, depositVault.totalSupply(), "totalSupplyMismatch"
        );

        // verify fee Recipient has recieved correct amount of fee
        assertEq(
            feeRecipientBalanceBefore + expectedFee,
            token.balanceOf(feeRecipient),
            "FeeRecipientBalanceMismatch"
        );

        // Verify Operator has received correct amount of assets
        assertEq(
            operatorBalanceBefore + assetsWithoutFee,
            token.balanceOf(address(operator)),
            "OperatorBalanceMismatch"
        );

        // Verify fundManager contract has been correct amount of assets deducted
        assertEq(
            fundManagerContractBalanceBefore - assetsWithFee,
            token.balanceOf(address(fundManager)),
            "FundManagerBalanceMismatch"
        );
    }

    function test_flashRedeem_Success_OnTotalAmount() public mintAssetForOtherUsers {
        // uint256 aliceDepositAmount = getQuantizedValue(100);
        // // ensure other users also mint, this does not affect the flow
        // vm.startPrank(users.alice);
        // depositVault.mint(aliceDepositAmount, users.alice);
        // vm.stopPrank();

        uint256 aggUnderlyingBalance = depositVault.aggregatedUnderlyingBalances();
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 operatorBalanceBefore = token.balanceOf(address(operator));
        uint256 fundManagerContractBalanceBefore = token.balanceOf(address(fundManager));

        address feeRecipient = depositVault.getFeeRecipient();
        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        uint256 sharesToRedeem = depositVault.balanceOf(address(operator));
        assertEq(sharesToRedeem, INITIAL_OPERATOR_DEPOSIT_AMOUNT);

        // sanity check to ensure the shares
        assertEq(sharesToRedeem, getQuantizedValue(100), "Incorrect ExpectedShares");

        uint256 assetsWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 expectedFee = Math.mulDiv(assetsWithFee, 1e15, 1e15 + 1e18, Math.Rounding.Ceil);
        uint256 assetsWithoutFee = assetsWithFee - expectedFee;

        assertEq(assetsWithFee, getQuantizedValue(100), "assetsWithFee not equal expectations");
        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), sharesToRedeem, "");
        vm.stopPrank();

        // verify aggregated underlying balance was updated correctly
        assertEq(aggUnderlyingBalance - assetsWithFee, depositVault.aggregatedUnderlyingBalances());

        // verify total supply has decreased by `sharesToRedeem`
        assertEq(
            totalSupplyBefore - sharesToRedeem, depositVault.totalSupply(), "totalSupplyMismatch"
        );

        // verify fee Recipient has recieved correct amount of fee
        assertEq(
            feeRecipientBalanceBefore + expectedFee,
            token.balanceOf(feeRecipient),
            "FeeRecipientBalanceMismatch"
        );

        // Verify Operator has received correct amount of assets
        assertEq(
            operatorBalanceBefore + assetsWithoutFee,
            token.balanceOf(address(operator)),
            "OperatorBalanceMismatch"
        );

        // Verify fundManager contract has been correct amount of assets deducted
        assertEq(
            fundManagerContractBalanceBefore - assetsWithFee,
            token.balanceOf(address(fundManager)),
            "FundManagerBalanceMismatch"
        );
    }

    function test_flashRedeem_Emits_FlashRedeemFulfilledEvent() public mintAssetForOtherUsers {

        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 assetsWithFee = depositVault.convertToAssets(shares);
        uint256 assetsWithoutFee = depositVault.previewFlashRedeem(shares);
        uint256 fee = assetsWithFee - assetsWithoutFee;

        vm.startPrank(address(operatorOwner));
        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.FlashRedeemFulfilled({
            initiator: operatorOwner,
            operator: address(operator),
            receiver: address(operator),
            shares: shares,
            assetsWithoutFee: assetsWithoutFee,
            fee: fee
        });
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Emits_FundsAddedAndFlashRedemptionFulfilled() public mintAssetForOtherUsers {

        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 assetsWithFee = depositVault.convertToAssets(shares);
        uint256 aggregatedBalance = depositVault.aggregatedUnderlyingBalances();

        vm.startPrank(address(operatorOwner));
        vm.expectEmit(true, true, true, true);
        emit VaultFundManager.FundsAddedAndFlashRedemptionFulfilled({
            initiator: operatorOwner,
            operator: address(operator),
            shares: shares,
            assetsWithFee: assetsWithFee,
            newAggregatedBalance: aggregatedBalance - assetsWithFee
        });
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Zero operator address
    function test_flashRedeem_Revert_ZeroAddressOperator() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert("VaultFundManager__UnauthorizedCaller()");
        fundManager.flashRedeem(address(0), shares, "");
        vm.stopPrank();
    }

    // Zero shares input
    function test_flashRedeem_Revert_ZeroShares() public {
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(VaultFundManager.VaultFundManager__ZeroAmount.selector);
        fundManager.flashRedeem(address(operator), 0, "");
        vm.stopPrank();
    }

    // Insufficient FundManager balance
    function test_flashRedeem_Revert_InsufficientBalance() public {
        // Drain fundManager tokens
        deal(address(token), address(fundManager), 0);
        uint256 shares = getQuantizedValue(1);
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(VaultFundManager.VaultFundManager__InsufficientBalance.selector);
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Aggregated underlying balance is zero
    function test_flashRedeem_Revert_AggregateBalanceZero() public {
        // Set aggregatedUnderlyingBalances to 0
        vm.startPrank(users.admin);
        // Force underlying balance update to zero
        depositVault.onUnderlyingBalanceUpdate(0);
        vm.stopPrank();
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(VaultFundManager.VaultFundManager__ZeroAmount.selector);
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Aggregated underlying balance is less than required asset amount
    function test_flashRedeem_Revert_AggregateBalanceLessThanAssetAmount() public {
        assertEq(depositVault.balanceOf(
            address(operator)),
            getQuantizedValue(100), 
            "InitialOperatorBalanceMismatch"
        );

        uint256 newUnderlyingBalance = getQuantizedValue(50);

        // Set aggregatedUnderlyingBalances to getQuantizedValue(50); (half of operator balance)
        vm.startPrank(users.admin);
        // updating the onUnderlyingBalanceUpdate will change the share price to 0.5 tokens
        depositVault.onUnderlyingBalanceUpdate(newUnderlyingBalance); // this will lead to vault getting paused
        IERC20(token).transfer(address(depositVault), getQuantizedValue(50)); // ensure the price of 1 share = 1 token ()
        depositVault.unpause(); // unpause to proceed with test
        vm.stopPrank();
 
        vm.roll(block.number + 1);

        // redeem full operator balance
        uint256 shares = depositVault.balanceOf(address(operator)); // getQuantizedValue(100); shares
        uint256 assetsWithFee = depositVault.convertToAssets(shares);

        assertEq(shares, getQuantizedValue(100), "share mismatch");
        assertGt(assetsWithFee, newUnderlyingBalance, "assetsWithFee should be greater than `newUnderlyingBalance` for test");

        vm.startPrank(address(operatorOwner));
        vm.expectRevert(abi.encodeWithSignature("VaultFundManager__InvalidCurrentAggregateBalance()"));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Created new fund manager under which the old correct operator is not whitelisted
    function test_flashRedeem_Revert_FundManagerNotWhitelisted() public {
        // fresh manager without whitelisting
        VaultFundManager freshManager = new VaultFundManager(payable(address(depositVault)));
        deal(address(token), address(freshManager), getQuantizedValue(1_000_000));

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(operatorOwner);
        // should revert due to isWhitelisted modifier
        vm.expectRevert("VaultFundManager__UnauthorizedCaller()");
        freshManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Confirm that funds are transferred from Fund Manager to MultipliVault
    function test_flashRedeem_Calls_TransferFromVaultManagerToMultipliVault() public mintAssetForOtherUsers {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amount = depositVault.convertToAssets(shares);

        vm.startPrank(address(operatorOwner));

        // verify call
        vm.expectCall(address(depositVault), abi.encodeWithSelector(
            token.transfer.selector, address(depositVault), amount)
        );
        fundManager.flashRedeem(address(operator), shares, "");

        vm.stopPrank();
    }

    // Invalid operator address in MultipliVault
    function test_vaultFlashRedeem_Revert_OperatorZeroAddress() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);

        vm.startPrank(address(fundManager));
        vm.expectRevert("Errors__InvalidOperatorAddress()");
        depositVault.flashRedeem(address(operator), address(0), address(operator), shares, amountWithFee, "");
        vm.stopPrank();
    }

    // Invalid receiver address in Vault
    function test_vaultFlashRedeem_Revert_InvalidReceiver() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.Errors__InvalidReceiverAddress.selector);
        depositVault.flashRedeem(address(operator), address(operator), address(0), shares,amountWithFee, "");
        vm.stopPrank();
    }

    // Vault paused
    function test_flashRedeem_Revert_VaultPaused() public {
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        uint256 shares = depositVault.balanceOf(address(operator));

        uint256 fundManagerBalance = token.balanceOf(address(fundManager));

        vm.startPrank(address(operatorOwner));
        vm.expectRevert("EnforcedPause()");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // verify funds have not been moved
        assertEq(fundManagerBalance, token.balanceOf(address(fundManager)));
    }

    // Confirm that funds are transferred from Fund Manager to MultipliVault and an event is emitted
    function test_vaultFlashRedeem_Emits_OnTransferFromVaultToOperator() public mintAssetForOtherUsers {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amount = depositVault.convertToAssets(shares);
        uint256 amountWithoutFee = depositVault.previewFlashRedeem(shares);

        vm.startPrank(address(operatorOwner));

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(depositVault), address(operator), amountWithoutFee);
        
        vm.expectCall(address(token), 
            abi.encodeWithSelector(token.transfer.selector, address(operator), amountWithoutFee)
        );
        fundManager.flashRedeem(address(operator), shares, "");

        vm.stopPrank();
    }


    // FundManager lacks permission to update aggregated balance
    function test_flashRedeem_Revert_NoPermissionOnUpdate() public {
        // revoke role
        vm.startPrank(users.admin);
        MockAuthority(address(authority)).setUserRole(
            address(fundManager), FUND_MANAGER_CONTRACT_ROLE, false
        );
        vm.stopPrank();

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        // revert due to missing role in onUnderlyingBalanceUpdate
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Operator fails to return shares → revert SharesNotReturned
    function test_flashRedeem_Reverts_OperatorFailsToReturnShares() public {
        // deploy operator 
        MockMaliciousOperator badOperator = new MockMaliciousOperator();
        badOperator.setVault(depositVault);
        deal(address(token), address(badOperator), getQuantizedValue(10_000)); // bad operator has sufficient balance to mint shares
        badOperator.mint(INITIAL_OPERATOR_DEPOSIT_AMOUNT); // mint some shares

        vm.prank(users.admin);
        depositVault.manage(
            address(fundManager),
            abi.encodeWithSelector(
                fundManager.updateUserOperatorWhitelist.selector, operatorOwner, address(badOperator), true
            ),
            0
        );

        uint256 shares = depositVault.balanceOf(address(badOperator)); 

        vm.startPrank(address(operatorOwner));
        vm.expectRevert(abi.encodeWithSignature("Errors__SharesNotReturned()"));
        fundManager.flashRedeem(address(badOperator), shares, "");
        vm.stopPrank();
    }

    // one operator tries to drain the shares of another operator
    function test_flashRedeem_Success_AttackerCallsOperatorContractFundsNotSentToBadOperator() public {
        address badUser = makeAddr("aisen");
        
        // deploy operator 
        MockMaliciousOperator badOperator = new MockMaliciousOperator();
        badOperator.setVault(depositVault);
        deal(address(token), address(badOperator), getQuantizedValue(10_000)); // bad operator has sufficient balance to mint shares
        badOperator.mint(INITIAL_OPERATOR_DEPOSIT_AMOUNT); // mint some shares

        vm.startPrank(users.admin);

        // whitelist baduser to call `operator` contract
        depositVault.manage(
            address(fundManager),
            abi.encodeWithSelector(
                fundManager.updateUserOperatorWhitelist.selector, badUser, address(operator), true
            ),
            0
        );
        // whitelist baduser to call `badOperator` contract
        depositVault.manage(
            address(fundManager),
            abi.encodeWithSelector(
                fundManager.updateUserOperatorWhitelist.selector, badUser, address(badOperator), true
            ),
            0
        );
        vm.stopPrank();

        // fetch the shares owned by operator
        uint256 shares = depositVault.balanceOf(address(operator));

        uint256 operatorAssetBalanceBefore = token.balanceOf(address(operator));

        uint256 assetAmountWithFee = depositVault.convertToAssets(shares);
        uint256 assetAmountWithoutFee = depositVault.previewFlashRedeem(shares);

        uint256 badUserAssetBalance = IERC20(token).balanceOf(badUser);
        uint256 badUserRecipientTokenBalance = depositVault.balanceOf(address(badUser));

        uint256 badOpAssetBalance = IERC20(token).balanceOf(address(badOperator));
        uint256 badOpRecipientTokenBalance = depositVault.balanceOf(address(badOperator));

        vm.startPrank(address(badUser));
        // vm.expectRevert();
        // `bad user` has permissions to call `flashRedeem` using OperatorContract as param
        // `bad user` sets `operator` param as `operator contract` 
        // and shares as the shares owned by `operator`
        // in this case, we cannot prevent `badUser` from initiating the request since bad user
        // is whitelisted to call using operator param
        // But we can assertain that the funds will be received by OperatorContract and not badOperator contract

        // Confirm fund transfer from VaultFundManager contract to MultipliVault contract
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(fundManager), address(depositVault), assetAmountWithFee);
        vm.expectCall(address(token), abi.encodeWithSelector(token.transfer.selector, address(depositVault), assetAmountWithFee));

        // Confirm fund transfer from MultipliVault contract to Operator contract
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(depositVault), address(operator), assetAmountWithoutFee);
        vm.expectCall(address(token), abi.encodeWithSelector(token.transfer.selector, address(operator), assetAmountWithoutFee));
        // funds to fee recipient
        vm.expectCall(
            address(token), 
            abi.encodeWithSelector(
                token.transfer.selector, 
                address(depositVault.getFeeRecipient()), 
                assetAmountWithFee - assetAmountWithoutFee //fee
            )
        );
        fundManager.flashRedeem({operator: address(operator), shares: shares, data: ""});

        vm.stopPrank();


        // verify operator contract has received the assets
        assertEq(token.balanceOf(address(operator)), operatorAssetBalanceBefore + assetAmountWithoutFee, "operator asset balance mismatch");

        // verify the shares owned by operator has been modified
        assertEq(depositVault.balanceOf(address(operator)), 0, "OperatorBalance should be 0");

        // verify bad user balance has not changed
        assertEq(badUserAssetBalance, IERC20(token).balanceOf(badUser), "bad user asset mismatch");
        assertEq(badUserRecipientTokenBalance, depositVault.balanceOf(address(badUser)), "bad user share mismatch");

        // verify bad Operator balance has not changed
        assertEq(badOpAssetBalance, IERC20(token).balanceOf(address(badOperator)), "bad operator asset mismatch");
        assertEq(badOpRecipientTokenBalance, depositVault.balanceOf(address(badOperator)), "bad operator share mismatch");

    }

    function test_flashRedeem_BurnsSharesFromVault() public mintAssetForOtherUsers {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithoutFee = depositVault.previewFlashRedeem(shares);
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 shareBalanceDepositVaultBefore = depositVault.balanceOf(address(depositVault));
        
        vm.startPrank(address(operatorOwner));
        // verify transfer of shares from MultipliVault to 0 -> signfies shares burnt
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(depositVault), address(0), shares);
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // Verify total Supply was deducted by `shares` amount
        assertEq(depositVault.totalSupply(), totalSupplyBefore - shares, "totalSupply mismatch");

        // Verify the shares owned by the Vault has not been modified
        assertEq(depositVault.balanceOf(address(depositVault)), shareBalanceDepositVaultBefore, "DepositVault share mismatch");
    }

    // Fee is zero then succeed, skip fee transfer
    function test_flashRedeem_Success_WithZeroFee() public mintAssetForOtherUsers {
        vm.startPrank(users.admin);
        // set flash redemption fee as 0
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 0}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = depositVault.convertToAssets(shares);

        uint256 feeRecipientAssetBalanceBefore = token.balanceOf(address(depositVault.getFeeRecipient()));
        
        vm.startPrank(address(operatorOwner));
        // verify amount is sent to Operator through Transfer Event

        // verify transfer between VaultFundManager to Multipli Vault
        vm.expectCall(address(token), abi.encodeWithSelector(token.transfer.selector, address(depositVault), amountWithFee));
        // Verify transfer between MultipliVault to Operator
        vm.expectCall(address(token), abi.encodeWithSelector(token.transfer.selector, address(operator), amountWithFee));
        vm.expectCall({
            callee: address(token),
            data: abi.encodeWithSelector(token.transfer.selector, depositVault.getFeeRecipient(), amountWithFee),
            count: 0
        }); // ensure call is not made to fee recipient

        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // Verify fee recipient has not received any funds
        assertEq(feeRecipientAssetBalanceBefore, token.balanceOf(address(depositVault.getFeeRecipient())), "FeeRecipient balance mismatch");

    }

    function test_flashRedeem_Revert_NoAuth_OnUnderlyingUpdate() public {
        vm.prank(users.admin);
        MockAuthority(address(authority)).setUserRole(
            address(fundManager), FUND_MANAGER_CONTRACT_ROLE, false
        );

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()")); // Access control fail
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_DirectCallToVault_UnauthorizedSender() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()")); // No requiresAuth
        depositVault.flashRedeem(users.alice, address(operator), address(operator), shares,amountWithFee, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_DirectCallToVault() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(address(operator));
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()")); // unauthorized sender (operator being sender)
        depositVault.flashRedeem(
            address(operator), address(operator), address(operator), shares, amountWithFee, "" 
        );
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_ConvertToAssetsZero() public {
        // artificially make totalAssets = 0
        vm.prank(users.admin);
        depositVault.onUnderlyingBalanceUpdate(0);

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert("VaultFundManager__ZeroAmount()");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Success_MultipleFlashRedeems() public {
        for (uint256 i = 0; i < 5; i++) {
            MockOperator op = new MockOperator();
            op.setVault(depositVault);

            vm.prank(users.admin);
            depositVault.manage(
                address(fundManager),
                abi.encodeWithSelector(
                    fundManager.updateUserOperatorWhitelist.selector, operatorOwner, address(op), true
                ),
                0
            );

            deal(address(token), address(op), getQuantizedValue(10));

            vm.prank(address(op));
            IERC20(token).approve(address(depositVault), getQuantizedValue(10));
            op.mint(getQuantizedValue(10));

            deal(address(token), address(fundManager), getQuantizedValue(10));

            vm.startPrank(operatorOwner);
            fundManager.flashRedeem(address(op), getQuantizedValue(10), "");
            vm.stopPrank();
            
            // increment block *after* redeem
            vm.roll(block.number + 1);

        }
    }

    function test_flashRedeem_Revert_PricePerShareSlippage() public {
        uint256 shares = depositVault.balanceOf(address(operator));

        // Force underlying balance near zero
        vm.prank(users.admin);
        depositVault.onUnderlyingBalanceUpdate(1); // pauses the contract

        vm.roll(block.number + 1);

        vm.startPrank(address(operatorOwner));
        vm.expectRevert("EnforcedPause()"); // pause as inside logic of onUnderlyingBalanceUpdate
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }
    

    function test_flashRedeem_InvalidAssetsWithFeesPassed() public mintAssetForOtherUsers {
    // This test simulates a scenario where the Vault Fund Manager attempts to manipulate
    // the assets-to-shares conversion by passing invalid/mismatched amounts to `flashRedeem`.
    // It ensures that such manipulations affect the price per share as expected, helping
    // detect potential vulnerabilities in the vault accounting logic.

        uint256 aggUnderlyingBalance = depositVault.aggregatedUnderlyingBalances();
        uint256 sharesToRedeem = depositVault.balanceOf(address(operator)) / 2;
        assertEq(sharesToRedeem, INITIAL_OPERATOR_DEPOSIT_AMOUNT / 2);

        // sanity check to ensure the shares
        assertEq(sharesToRedeem, getQuantizedValue(50), "Incorrect ExpectedShares");

        uint256 amountWithFee = depositVault.convertToAssets(sharesToRedeem);
        amountWithFee += getQuantizedValue(10);
        sharesToRedeem -= getQuantizedValue(10);

        uint256 oldPricePerShare = depositVault.lastPricePerShare();
        vm.startPrank(address(fundManager));
        depositVault.flashRedeem(address(operator), address(operator), address(operator), sharesToRedeem, amountWithFee, "");
        updateUnderlyingBalance(aggUnderlyingBalance - amountWithFee);

        uint256 newPricePerShare = depositVault.lastPricePerShare();

        assertGe(_calculatePercentageChange(oldPricePerShare, newPricePerShare), 1e15);
        vm.stopPrank();
    }


    function test_vaultFlashRedeem_Revert_ZeroShares() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0; 
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.Errors__SharesAmountZero.selector);
        depositVault.flashRedeem(address(operator), address(operator), address(operator), 0,amountWithFee, "");
        vm.stopPrank();
    }

    function test_vaultFlashRedeem_Revert_InvalidOperator() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.Errors__InvalidOperatorAddress.selector);
        depositVault.flashRedeem(address(operator), address(0), address(operator), shares,amountWithFee, "");
        vm.stopPrank();
    }

    function test_vaultFlashRedeem_Revert_InvalidAssetsAmount() public {
        uint256 shares = depositVault.balanceOf(address(operator));

        // drain tokens from vault to force insufficient liquidity
        deal(address(token), address(depositVault), 0);
        uint256 amountWithFee = 0;
        
        amountWithFee = depositVault.convertToAssets(shares);
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.Errors__InvalidAssetsAmount.selector);
        depositVault.flashRedeem(
            address(operator), address(operator), address(operator), shares,amountWithFee, ""
        );
        vm.stopPrank();
    }

    // todo: fix this case -> if fee recipient is not set, it should revert
    function test_flashRedeem_Success_FeeRecipientZero_FeeAddedToVault() public mintAssetForOtherUsers{

        // 1) Deploy ZeroFeeRecipient stub and set it on the vault,
        ZeroFeeRecipient zeroStub = new ZeroFeeRecipient();
        vm.prank(users.admin);
        depositVault.setFeeContract(zeroStub);

        // 2) Assert that getFeeRecipient returns address(0) as intended
        assertEq(depositVault.getFeeRecipient(), address(0), "FeeRecipient should be zero");

        // 3) Execute flashRedeem to verify it works without fee collection
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 assetsWithFee = depositVault.convertToAssets(shares);
        uint256 assetsWithoutFee = depositVault.previewFlashRedeem(shares);
        uint256 fee = assetsWithFee - assetsWithoutFee;
        uint256 vaultAssetBalance = token.balanceOf(address(depositVault));

        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // 4) Confirm that asset balance is added to the vault
        assertEq(vaultAssetBalance, token.balanceOf(address(depositVault)) + fee);
    }

    function test_flashRedeem_Success_ZeroFeeWithZeroFeeRecipient() public mintAssetForOtherUsers {
        // Set ZeroFeeRecipient stub (returns address(0))
        ZeroFeeRecipient zeroStub = new ZeroFeeRecipient();
        vm.prank(users.admin);
        depositVault.setFeeContract(zeroStub);

        // Sanity: Confirm fee recipient is zero
        assertEq(depositVault.getFeeRecipient(), address(0), "Fee recipient should be zero");

        // Execute flashRedeem without issues
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 assetsWithFee = depositVault.convertToAssets(shares);
        uint256 assetsWithoutFee = depositVault.previewFlashRedeem(shares);
        uint256 fee = assetsWithFee - assetsWithoutFee;
        uint256 vaultAssetBalance = token.balanceOf(address(depositVault));

        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        assertEq(vaultAssetBalance, token.balanceOf(address(depositVault)) + fee);
    }


    function test_flashRedeem_Succeeds_ForWhitelistedUser() public {
        // Whitelist operatorOwner for operator
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint operator shares
        deal(address(token), address(operator), getQuantizedValue(50));
        vm.startPrank(address(operator));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator.mint(getQuantizedValue(50));
        vm.stopPrank();

        // Fund vault for flash redeem
        deal(address(token), address(fundManager), getQuantizedValue(50));

        // Whitelisted user should succeed
        vm.startPrank(operatorOwner);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
        vm.stopPrank();
    }

    function test_flashRedeem_Reverts_ForNonWhitelistedUser() public {
        address otherUser = makeAddr("otherUser");

        // Whitelist only operatorOwner (not otherUser)
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint shares for operator
        deal(address(token), address(operator), getQuantizedValue(50));
        vm.startPrank(address(operator));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator.mint(getQuantizedValue(50));
        vm.stopPrank();

        deal(address(token), address(fundManager), getQuantizedValue(50));

        // Non-whitelisted user should fail
        vm.startPrank(otherUser);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
        vm.stopPrank();
    }

    function test_flashRedeem_OnlyWhitelistedUserCanCallOperator() public {
        address otherUser = makeAddr("otherUser");

        // Whitelist only operatorOwner
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint operator shares
        deal(address(token), address(operator), getQuantizedValue(50));
        vm.startPrank(address(operator));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator.mint(getQuantizedValue(50));
        vm.stopPrank();

        deal(address(token), address(fundManager), getQuantizedValue(50));

        // Success path for whitelisted user
        vm.startPrank(operatorOwner);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
        vm.stopPrank();

        // Failure path for unrelated user
        vm.startPrank(otherUser);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
        vm.stopPrank();
    }

    function test_revert_flashRedeem_WhenOperatorNotWhitelisted() public {
        // Use vault.manage to call whitelist update
        vm.startPrank(users.admin);
        depositVault.manage(
            address(fundManager),
            abi.encodeWithSelector(
                fundManager.updateUserOperatorWhitelist.selector,
                operatorOwner,
                address(operator),
                false
            ),
            0
        );
        vm.stopPrank();
        vm.prank(operatorOwner);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
    }

    function test_flashRedeemFailsAfterWhitelistRevoked() public {
        // Setup: operatorOwner2 and its operator
        (address operatorOwner2,) = makeAddrAndKey("operatorOwner2");
        MockOperator operator2 = new MockOperator();
        operator2.setVault(depositVault);

        // Whitelist both operator-owner pairs and revoke one
        vm.startPrank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner2, address(operator2), true);
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), false);
        vm.stopPrank();

        // Sanity check
        assertFalse(fundManager.whitelistedUserOperator(operatorOwner, address(operator)));
        assertTrue(fundManager.whitelistedUserOperator(operatorOwner2, address(operator2)));

        // Mint & approve for operator2
        deal(address(token), address(operator2), getQuantizedValue(50));
        vm.startPrank(address(operator2));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator2.mint(getQuantizedValue(50));
        vm.stopPrank();

        // Mint & approve for operator
        deal(address(token), address(operator), getQuantizedValue(50));
        vm.startPrank(address(operator));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator.mint(getQuantizedValue(50));
        vm.stopPrank();

        // Fund the fundManager
        deal(address(token), address(fundManager), getQuantizedValue(100));

        // Success: operatorOwner2 can redeem
        vm.startPrank(operatorOwner2);
        fundManager.flashRedeem(address(operator2), getQuantizedValue(50), "");
        vm.stopPrank();

        // Fail: operatorOwner cannot redeem after revocation
        vm.startPrank(operatorOwner);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), getQuantizedValue(50), "");
        vm.stopPrank();
    }

    function test_flashRedeemFailsForNonWhitelistedOperator() public {
        address operatorOwner2;
        uint256 key;
        (operatorOwner2, key) = makeAddrAndKey("operatorOwner2");

        MockOperator operator2 = new MockOperator();
        operator2.setVault(depositVault);

        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        deal(address(token), address(operator2), getQuantizedValue(50));
        vm.prank(address(operator2));
        IERC20(token).approve(address(depositVault), getQuantizedValue(50));
        operator2.mint(getQuantizedValue(50));

        deal(address(token), address(fundManager), getQuantizedValue(50));

        // Operator2 is not whitelisted
        vm.prank(operatorOwner2);
        vm.expectRevert(VaultFundManager.VaultFundManager__UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator2), getQuantizedValue(50), "");
    }

   /**
     * Ensures share price consistency during flash redemption.
     * Critical for Euler integration where leveraged positions are unwound.
     * Verifies that convertToAssets(shares) remains unchanged between flash loan
     * initiation and callback, preventing incorrect redemptions or exploits.
    */
    function testFuzz_flashRedeem_SharePriceConsistency_DuringCallback(uint256 initialAssets) public mintAssetForOtherUsers {
        // Bound the fuzz input between 100 tokens and 2M tokens
        vm.assume(initialAssets >= getQuantizedValue(100) && initialAssets <= getQuantizedValue(2_000_000));

        SharePriceConsistencyOperator consistencyOperator = new SharePriceConsistencyOperator();
        consistencyOperator.setVault(depositVault, address(token)); 

        vm.startPrank(users.admin);
        depositVault.onUnderlyingBalanceUpdate(initialAssets + getQuantizedValue(100));
        vm.roll(block.number + 1); 
        depositVault.unpause();
        vm.stopPrank();

        // Setup operator with funds
        deal(address(token), address(consistencyOperator), initialAssets);
        
        vm.startPrank(address(consistencyOperator));
        IERC20(token).approve(address(depositVault), type(uint256).max);
        depositVault.deposit(initialAssets, address(consistencyOperator));
        vm.stopPrank();

        // Whitelist operator
        vm.prank(users.admin);
        depositVault.manage(
            address(fundManager),
            abi.encodeWithSelector(
                fundManager.updateUserOperatorWhitelist.selector, 
                operatorOwner, 
                address(consistencyOperator), 
                true
            ),
            0
        );

        uint256 shares = depositVault.balanceOf(address(consistencyOperator));
        uint256 assetsWithFeeAtStart = depositVault.convertToAssets(shares);

        // Operator tracks expected values
        consistencyOperator.setExpectedValues(shares, assetsWithFeeAtStart);

        // Give fund manager liquidity to support flashRedeem
        deal(address(token), address(fundManager), assetsWithFeeAtStart);

        // Approve repayment during flashRedeem
        vm.startPrank(address(consistencyOperator));
        IERC20(token).approve(address(fundManager), type(uint256).max);
        vm.stopPrank();

        // Execute flashRedeem
        vm.startPrank(operatorOwner);
        fundManager.flashRedeem(address(consistencyOperator), shares, "");
        vm.stopPrank();

        // Final consistency check
        assertTrue(consistencyOperator.consistencyVerified(), "Share price inconsistent during callback");
    }

}
