// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {FeeBase} from "./Base.t.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestRegisterAsset is FeeBase {
    function testRegisterAssetRevertsWhenCalledByNonOwner() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.startPrank(madara);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, madara));
        feeContract.registerAsset(address(USDC), config);
        vm.stopPrank();
    }

    function testRegisterAssetRevertsWhenAssetAddressIsZero() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee, 
                feeRecipient: feeRecipient
            });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.registerAsset(address(0), config);
        vm.stopPrank();
    }

    function testRegisterAssetRevertsWhenAssetAlreadyRegistered() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.startPrank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.expectRevert(IVariableVaultFee.AssetAlreadyRegistered.selector);
        feeContract.registerAsset(address(USDC), config);
        vm.stopPrank();
    }

    function testRegisterAssetRevertsWhenFeeRecipientIsZeroAddress() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee, 
                feeRecipient: address(0)
            });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.InvalidAssetConfig.selector);
        feeContract.registerAsset(address(USDC), config);
        vm.stopPrank();
    }

    function testRegisterAssetRevertsWhenPercentageFeeExceedsMaximum() public {
        IVariableVaultFee.FeeConfig memory highPercentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 6e16 // > 5e16
        });

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: highPercentageFee,
            depositFee: highPercentageFee,
            instantWithdrawalFee: highPercentageFee,
            flashRedeemFee: highPercentageFee,
            feeRecipient: feeRecipient
        });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.InvalidAssetConfig.selector);
        feeContract.registerAsset(address(USDC), config);
        vm.stopPrank();
    }

    function testRegisterAssetSuccess() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.startPrank(naruto);

        vm.expectEmit(true, true, true, true);
        emit IVariableVaultFee.RegisterAsset(naruto, address(USDC), config);

        feeContract.registerAsset(address(USDC), config);

        assertTrue(feeContract.isAssetRegistered(address(USDC)));
        (
            IVariableVaultFee.FeeConfig memory withdrawFee,
            IVariableVaultFee.FeeConfig memory depositFee,
            IVariableVaultFee.FeeConfig memory instantWithdrawFee,
            IVariableVaultFee.FeeConfig memory flashRedeemFee,
            address recipient
        ) = feeContract.assetFee(address(USDC));

        assertEq(withdrawFee.feeAmount, 10e6);
        assertEq(uint8(withdrawFee.feeType), uint8(IVariableVaultFee.FeeType.FLAT));

        assertEq(depositFee.feeAmount, 10e6);
        assertEq(uint8(depositFee.feeType), uint8(IVariableVaultFee.FeeType.FLAT));

        assertEq(instantWithdrawFee.feeAmount, 10e6);
        assertEq(uint8(instantWithdrawFee.feeType), uint8(IVariableVaultFee.FeeType.FLAT));

        assertEq(flashRedeemFee.feeAmount, 10e6);
        assertEq(uint8(flashRedeemFee.feeType), uint8(IVariableVaultFee.FeeType.FLAT));

        assertEq(recipient, feeRecipient);

        vm.stopPrank();
    }
}
