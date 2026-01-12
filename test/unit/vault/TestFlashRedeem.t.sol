// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import { BaseTest } from "./Base.t.sol";
import { VaultFundManager } from "src/managers/VaultFundManager.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MockOperator, MockMaliciousOperator } from "../../mocks/MockOperator.sol";
import { MockAuthority } from "../../mocks/MockAuthority.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVariableVaultFee } from "src/interfaces/IVariableVaultFee.sol";
import { MultipliVault } from "src/vault/MultipliVault.sol";
import { MockMultipliVaultV2 } from "../../mocks/MockMultipliVaultV2.sol";
import { ZeroFeeRecipient } from "../../mocks/ZeroFeeRecipient.sol";
import {IMultipliVault} from "src/interfaces/IMultipliVault.sol";

import { Errors } from "src/libraries/Errors.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// todo: should be moved to `test/managers/`
contract TestFlashRedeem is BaseTest {
    address operatorOwner;
    uint256 operatorOwnerKey;

    VaultFundManager fundManager;
    MockOperator operator;

    uint256 INITIAL_OPERATOR_DEPOSIT_AMOUNT = 100e6;

    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank(users.admin);

        // setup operatorOwner
        (operatorOwner, operatorOwnerKey) = makeAddrAndKey("operatorOwner");
        deal(operatorOwner, 10e18); // add eth balance
        deal(address(usdc), operatorOwner, 100_000e6); // add 100K usdc balance
        vm.label({ account: operatorOwner, newLabel: "operatorOwner" });

        // setup Operator contract
        operator = new MockOperator();
        deal(address(operator), 10e18); // add eth balance
        deal(address(usdc), address(operator), 1_000_000e6); // add 1M usdc balance
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
        deal(address(usdc), address(fundManager), 1_000_000e6); // ensure fund manager has 1M USDC

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

    function test_flashRedeem_Success_OnPartialAmount() public {
        uint256 aggUnderlyingBalance = depositVault.aggregatedUnderlyingBalances();
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 operatorBalanceBefore = usdc.balanceOf(address(operator));
        uint256 fundManagerContractBalanceBefore = usdc.balanceOf(address(fundManager));

        address feeRecipient = depositVault.getFeeRecipient();
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        uint256 sharesToRedeem = depositVault.balanceOf(address(operator)) / 2;
        assertEq(sharesToRedeem, INITIAL_OPERATOR_DEPOSIT_AMOUNT / 2);

        // sanity check to ensure the shares
        assertEq(sharesToRedeem, 50e6, "Incorrect ExpectedShares");

        uint256 assetsWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 expectedFee = Math.mulDiv(assetsWithFee, 1e15, 1e15 + 1e18, Math.Rounding.Ceil);
        uint256 assetsWithoutFee = assetsWithFee - expectedFee;

        assertEq(assetsWithFee, 50e6, "assetsWithFee not equal expectations");
        assertEq(expectedFee, 49_951, "expectedFee not equal expectations");

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
            usdc.balanceOf(feeRecipient),
            "FeeRecipientBalanceMismatch"
        );

        // Verify Operator has received correct amount of assets
        assertEq(
            operatorBalanceBefore + assetsWithoutFee,
            usdc.balanceOf(address(operator)),
            "OperatorBalanceMismatch"
        );

        // Verify fundManager contract has been correct amount of assets deducted
        assertEq(
            fundManagerContractBalanceBefore - assetsWithFee,
            usdc.balanceOf(address(fundManager)),
            "FundManagerBalanceMismatch"
        );
    }

    function test_flashRedeem_Success_OnTotalAmount() public {
        // uint256 aliceDepositAmount = 100e6;
        // // ensure other users also mint, this does not affect the flow
        // vm.startPrank(users.alice);
        // depositVault.mint(aliceDepositAmount, users.alice);
        // vm.stopPrank();

        uint256 aggUnderlyingBalance = depositVault.aggregatedUnderlyingBalances();
        uint256 totalSupplyBefore = depositVault.totalSupply();
        uint256 totalAssetsBefore = depositVault.totalAssets();
        uint256 operatorBalanceBefore = usdc.balanceOf(address(operator));
        uint256 fundManagerContractBalanceBefore = usdc.balanceOf(address(fundManager));

        address feeRecipient = depositVault.getFeeRecipient();
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        uint256 sharesToRedeem = depositVault.balanceOf(address(operator));
        assertEq(sharesToRedeem, INITIAL_OPERATOR_DEPOSIT_AMOUNT);

        // sanity check to ensure the shares
        assertEq(sharesToRedeem, 100e6, "Incorrect ExpectedShares");

        uint256 assetsWithFee = depositVault.convertToAssets(sharesToRedeem);
        uint256 expectedFee = Math.mulDiv(assetsWithFee, 1e15, 1e15 + 1e18, Math.Rounding.Ceil);
        uint256 assetsWithoutFee = assetsWithFee - expectedFee;

        assertEq(assetsWithFee, 100e6, "assetsWithFee not equal expectations");
        assertEq(expectedFee, 99_901, "expectedFee not equal expectations");

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
            usdc.balanceOf(feeRecipient),
            "FeeRecipientBalanceMismatch"
        );

        // Verify Operator has received correct amount of assets
        assertEq(
            operatorBalanceBefore + assetsWithoutFee,
            usdc.balanceOf(address(operator)),
            "OperatorBalanceMismatch"
        );

        // Verify fundManager contract has been correct amount of assets deducted
        assertEq(
            fundManagerContractBalanceBefore - assetsWithFee,
            usdc.balanceOf(address(fundManager)),
            "FundManagerBalanceMismatch"
        );
    }

    function test_flashRedeem_Emits_FlashRedeemFulfilledEvent() public {

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

    function test_flashRedeem_Emits_FundsAddedAndFlashRedemptionFulfilled() public {

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
        vm.expectRevert("UnauthorizedCaller()");
        fundManager.flashRedeem(address(0), shares, "");
        vm.stopPrank();
    }

    // Zero shares input
    function test_flashRedeem_Revert_ZeroShares() public {
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(VaultFundManager.ZeroAmount.selector);
        fundManager.flashRedeem(address(operator), 0, "");
        vm.stopPrank();
    }

    // Insufficient FundManager balance
    function test_flashRedeem_Revert_InsufficientBalance() public {
        // Drain fundManager USDC
        deal(address(usdc), address(fundManager), 0);
        uint256 shares = 1e6;
        vm.startPrank(address(operatorOwner));
        vm.expectRevert(VaultFundManager.InsufficientBalance.selector);
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
        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Aggregated underlying balance is less than required asset amount
    function test_flashRedeem_Revert_AggregateBalanceLessThanAssetAmount() public {
        assertEq(depositVault.balanceOf(
            address(operator)),
            100e6, 
            "InitialOperatorBalanceMismatch"
        );

        uint256 newUnderlyingBalance = 50e6;

        // Set aggregatedUnderlyingBalances to 50e6 (half of operator balance)
        vm.startPrank(users.admin);
        // updating the onUnderlyingBalanceUpdate will change the share price to 0.5 USDC
        depositVault.onUnderlyingBalanceUpdate(newUnderlyingBalance); // this will lead to vault getting paused
        IERC20(usdc).transfer(address(depositVault), 50e6); // ensure the price of 1 share = 1 usdc ()
        depositVault.unpause(); // unpause to proceed with test
        vm.stopPrank();
 
        vm.roll(block.number + 1);

        // redeem full operator balance
        uint256 shares = depositVault.balanceOf(address(operator)); // 100e6 shares
        uint256 assetsWithFee = depositVault.convertToAssets(shares);

        assertEq(shares, 100e6, "share mismatch");
        assertGt(assetsWithFee, newUnderlyingBalance, "assetsWithFee should be greater than `newUnderlyingBalance` for test");

        vm.startPrank(address(operatorOwner));
        vm.expectRevert("INVARIANT: InvalidCurrentAggregateBalance");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Created new fund manager under which the old correct operator is not whitelisted
    function test_flashRedeem_Revert_FundManagerNotWhitelisted() public {
        // fresh manager without whitelisting
        VaultFundManager freshManager = new VaultFundManager(payable(address(depositVault)));
        deal(address(usdc), address(freshManager), 1_000_000e6);

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(operatorOwner);
        // should revert due to isWhitelisted modifier
        vm.expectRevert("UnauthorizedCaller()");
        freshManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Confirm that funds are transferred from Fund Manager to MultipliVault
    function test_flashRedeem_Calls_TransferFromVaultManagerToMultipliVault() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amount = depositVault.convertToAssets(shares);

        vm.startPrank(address(operatorOwner));

        // verify call
        vm.expectCall(address(depositVault), abi.encodeWithSelector(
            usdc.transfer.selector, address(depositVault), amount)
        );
        fundManager.flashRedeem(address(operator), shares, "");

        vm.stopPrank();
    }

    // Invalid operator address in MultipliVault
    function test_vaultFlashRedeem_Revert_OperatorZeroAddress() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(fundManager));
        vm.expectRevert("InvalidOperatorAddress()");
        depositVault.flashRedeem(address(operator), address(0), address(operator), shares, "");
        vm.stopPrank();
    }

    // Invalid receiver address in Vault
    function test_vaultFlashRedeem_Revert_InvalidReceiver() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.InvalidReceiverAddress.selector);
        depositVault.flashRedeem(address(operator), address(operator), address(0), shares, "");
        vm.stopPrank();
    }

    // Vault paused
    function test_flashRedeem_Revert_VaultPaused() public {
        vm.startPrank(users.admin);
        depositVault.pause();
        vm.stopPrank();

        uint256 shares = depositVault.balanceOf(address(operator));

        uint256 fundManagerBalance = usdc.balanceOf(address(fundManager));

        vm.startPrank(address(operatorOwner));
        vm.expectRevert("EnforcedPause()");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // verify funds have not been moved
        assertEq(fundManagerBalance, usdc.balanceOf(address(fundManager)));
    }

    // Confirm that funds are transferred from Fund Manager to MultipliVault and an event is emitted
    function test_vaultFlashRedeem_Emits_OnTransferFromVaultToOperator() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amount = depositVault.convertToAssets(shares);
        uint256 amountWithoutFee = depositVault.previewFlashRedeem(shares);

        vm.startPrank(address(operatorOwner));

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(depositVault), address(operator), amountWithoutFee);
        
        vm.expectCall(address(usdc), 
            abi.encodeWithSelector(usdc.transfer.selector, address(operator), amountWithoutFee)
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
        vm.expectRevert("UNAUTHORIZED");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    // Operator fails to return shares → revert SharesNotReturned
    function test_flashRedeem_Reverts_OperatorFailsToReturnShares() public {
        // deploy operator 
        MockMaliciousOperator badOperator = new MockMaliciousOperator();
        badOperator.setVault(depositVault);
        deal(address(usdc), address(badOperator), 10_000e6); // bad operator has sufficient balance to mint shares
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
        vm.expectRevert(abi.encodeWithSignature("SharesNotReturned()"));
        fundManager.flashRedeem(address(badOperator), shares, "");
        vm.stopPrank();
    }

    // one operator tries to drain the shares of another operator
    function test_flashRedeem_Success_AttackerCallsOperatorContractFundsNotSentToBadOperator() public {
        address badUser = makeAddr("aisen");
        
        // deploy operator 
        MockMaliciousOperator badOperator = new MockMaliciousOperator();
        badOperator.setVault(depositVault);
        deal(address(usdc), address(badOperator), 10_000e6); // bad operator has sufficient balance to mint shares
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

        uint256 operatorAssetBalanceBefore = usdc.balanceOf(address(operator));

        uint256 assetAmountWithFee = depositVault.convertToAssets(shares);
        uint256 assetAmountWithoutFee = depositVault.previewFlashRedeem(shares);

        uint256 badUserAssetBalance = IERC20(usdc).balanceOf(badUser);
        uint256 badUserRecipientTokenBalance = depositVault.balanceOf(address(badUser));

        uint256 badOpAssetBalance = IERC20(usdc).balanceOf(address(badOperator));
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
        vm.expectCall(address(usdc), abi.encodeWithSelector(usdc.transfer.selector, address(depositVault), assetAmountWithFee));

        // Confirm fund transfer from MultipliVault contract to Operator contract
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(depositVault), address(operator), assetAmountWithoutFee);
        vm.expectCall(address(usdc), abi.encodeWithSelector(usdc.transfer.selector, address(operator), assetAmountWithoutFee));
        // funds to fee recipient
        vm.expectCall(
            address(usdc), 
            abi.encodeWithSelector(
                usdc.transfer.selector, 
                address(depositVault.getFeeRecipient()), 
                assetAmountWithFee - assetAmountWithoutFee //fee
            )
        );
        fundManager.flashRedeem({operator: address(operator), shares: shares, data: ""});

        vm.stopPrank();


        // verify operator contract has received the assets
        assertEq(usdc.balanceOf(address(operator)), operatorAssetBalanceBefore + assetAmountWithoutFee, "operator asset balance mismatch");

        // verify the shares owned by operator has been modified
        assertEq(depositVault.balanceOf(address(operator)), 0, "OperatorBalance should be 0");

        // verify bad user balance has not changed
        assertEq(badUserAssetBalance, IERC20(usdc).balanceOf(badUser), "bad user asset mismatch");
        assertEq(badUserRecipientTokenBalance, depositVault.balanceOf(address(badUser)), "bad user share mismatch");

        // verify bad Operator balance has not changed
        assertEq(badOpAssetBalance, IERC20(usdc).balanceOf(address(badOperator)), "bad operator asset mismatch");
        assertEq(badOpRecipientTokenBalance, depositVault.balanceOf(address(badOperator)), "bad operator share mismatch");

    }

    function test_flashRedeem_BurnsSharesFromVault() public {
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
    function test_flashRedeem_Success_WithZeroFee() public {
        vm.startPrank(users.admin);
        // set flash redemption fee as 0
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}),
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 0}),
                feeRecipient: address(users.feeRecipient)
            })
        );
        vm.stopPrank();

        uint256 shares = depositVault.balanceOf(address(operator));
        uint256 amountWithFee = depositVault.convertToAssets(shares);

        uint256 feeRecipientAssetBalanceBefore = usdc.balanceOf(address(depositVault.getFeeRecipient()));
        
        vm.startPrank(address(operatorOwner));
        // verify amount is sent to Operator through Transfer Event

        // verify transfer between VaultFundManager to Multipli Vault
        vm.expectCall(address(usdc), abi.encodeWithSelector(usdc.transfer.selector, address(depositVault), amountWithFee));
        // Verify transfer between MultipliVault to Operator
        vm.expectCall(address(usdc), abi.encodeWithSelector(usdc.transfer.selector, address(operator), amountWithFee));
        vm.expectCall({
            callee: address(usdc),
            data: abi.encodeWithSelector(usdc.transfer.selector, depositVault.getFeeRecipient(), amountWithFee),
            count: 0
        }); // ensure call is not made to fee recipient

        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // Verify fee recipient has not received any funds
        assertEq(feeRecipientAssetBalanceBefore, usdc.balanceOf(address(depositVault.getFeeRecipient())), "FeeRecipient balance mismatch");

    }

    function test_flashRedeem_Revert_NoAuth_OnUnderlyingUpdate() public {
        vm.prank(users.admin);
        MockAuthority(address(authority)).setUserRole(
            address(fundManager), FUND_MANAGER_CONTRACT_ROLE, false
        );

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert("UNAUTHORIZED"); // Access control fail
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_DirectCallToVault_UnauthorizedSender() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(users.alice);
        vm.expectRevert("UNAUTHORIZED"); // No requiresAuth
        depositVault.flashRedeem(users.alice, address(operator), address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_DirectCallToVault() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operator));
        vm.expectRevert("UNAUTHORIZED"); // unauthorized sender (operator being sender)
        depositVault.flashRedeem(
            address(operator), address(operator), address(operator), shares, ""
        );
        vm.stopPrank();
    }

    function test_flashRedeem_Revert_ConvertToAssetsZero() public {
        // artificially make totalAssets = 0
        vm.prank(users.admin);
        depositVault.onUnderlyingBalanceUpdate(0);

        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(operatorOwner));
        vm.expectRevert("ZeroAmount()");
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Success_MultipleFlashRedeems() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.roll(block.number + 1);
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

            deal(address(usdc), address(op), 10e6);

            vm.prank(address(op));
            IERC20(usdc).approve(address(depositVault), 10e6);
            op.mint(10e6);

            deal(address(usdc), address(fundManager), 10e6);

            vm.startPrank(operatorOwner);
            fundManager.flashRedeem(address(op), 10e6, "");
            vm.stopPrank();
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

    function test_vaultFlashRedeem_Revert_ZeroShares() public {
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.SharesAmountZero.selector);
        depositVault.flashRedeem(address(operator), address(operator), address(operator), 0, "");
        vm.stopPrank();
    }

    function test_vaultFlashRedeem_Revert_InvalidOperator() public {
        uint256 shares = depositVault.balanceOf(address(operator));
        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.InvalidOperatorAddress.selector);
        depositVault.flashRedeem(address(operator), address(0), address(operator), shares, "");
        vm.stopPrank();
    }

    function test_vaultFlashRedeem_Revert_InvalidAssetsAmount() public {
        uint256 shares = depositVault.balanceOf(address(operator));

        // drain USDC from vault to force insufficient liquidity
        deal(address(usdc), address(depositVault), 0);

        vm.startPrank(address(fundManager));
        vm.expectRevert(Errors.InvalidAssetsAmount.selector);
        depositVault.flashRedeem(
            address(operator), address(operator), address(operator), shares, ""
        );
        vm.stopPrank();
    }

    // todo: fix this case -> if fee recipient is not set, it should revert
    function test_flashRedeem_Success_FeeRecipientZero_FeeAddedToVault() public {

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
        uint256 vaultAssetBalance = usdc.balanceOf(address(depositVault));

        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        // 4) Confirm that asset balance is added to the vault
        assertEq(vaultAssetBalance, usdc.balanceOf(address(depositVault)) + fee);
    }

    function test_flashRedeem_Success_ZeroFeeWithZeroFeeRecipient() public {
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
        uint256 vaultAssetBalance = usdc.balanceOf(address(depositVault));

        vm.startPrank(address(operatorOwner));
        fundManager.flashRedeem(address(operator), shares, "");
        vm.stopPrank();

        assertEq(vaultAssetBalance, usdc.balanceOf(address(depositVault)) + fee);
    }


    function test_flashRedeem_Succeeds_ForWhitelistedUser() public {
        // Whitelist operatorOwner for operator
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint operator shares
        deal(address(usdc), address(operator), 50e6);
        vm.startPrank(address(operator));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator.mint(50e6);
        vm.stopPrank();

        // Fund vault for flash redeem
        deal(address(usdc), address(fundManager), 50e6);

        // Whitelisted user should succeed
        vm.startPrank(operatorOwner);
        fundManager.flashRedeem(address(operator), 50e6, "");
        vm.stopPrank();
    }

    function test_flashRedeem_Reverts_ForNonWhitelistedUser() public {
        address otherUser = makeAddr("otherUser");

        // Whitelist only operatorOwner (not otherUser)
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint shares for operator
        deal(address(usdc), address(operator), 50e6);
        vm.startPrank(address(operator));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator.mint(50e6);
        vm.stopPrank();

        deal(address(usdc), address(fundManager), 50e6);

        // Non-whitelisted user should fail
        vm.startPrank(otherUser);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), 50e6, "");
        vm.stopPrank();
    }

    function test_flashRedeem_OnlyWhitelistedUserCanCallOperator() public {
        address otherUser = makeAddr("otherUser");

        // Whitelist only operatorOwner
        vm.prank(address(depositVault));
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);

        // Mint operator shares
        deal(address(usdc), address(operator), 50e6);
        vm.startPrank(address(operator));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator.mint(50e6);
        vm.stopPrank();

        deal(address(usdc), address(fundManager), 50e6);

        // Success path for whitelisted user
        vm.startPrank(operatorOwner);
        fundManager.flashRedeem(address(operator), 50e6, "");
        vm.stopPrank();

        // Failure path for unrelated user
        vm.startPrank(otherUser);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), 50e6, "");
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
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), 50e6, "");
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
        deal(address(usdc), address(operator2), 50e6);
        vm.startPrank(address(operator2));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator2.mint(50e6);
        vm.stopPrank();

        // Mint & approve for operator
        deal(address(usdc), address(operator), 50e6);
        vm.startPrank(address(operator));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator.mint(50e6);
        vm.stopPrank();

        // Fund the fundManager
        deal(address(usdc), address(fundManager), 100e6);

        // Success: operatorOwner2 can redeem
        vm.startPrank(operatorOwner2);
        fundManager.flashRedeem(address(operator2), 50e6, "");
        vm.stopPrank();

        // Fail: operatorOwner cannot redeem after revocation
        vm.startPrank(operatorOwner);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator), 50e6, "");
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

        deal(address(usdc), address(operator2), 50e6);
        vm.prank(address(operator2));
        IERC20(usdc).approve(address(depositVault), 50e6);
        operator2.mint(50e6);

        deal(address(usdc), address(fundManager), 50e6);

        // Operator2 is not whitelisted
        vm.prank(operatorOwner2);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.flashRedeem(address(operator2), 50e6, "");
    }
}
