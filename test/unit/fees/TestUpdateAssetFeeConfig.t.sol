// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestUpdateAssetFeeConfig is FeeBase {
    function setUp() public override {
        super.setUp();
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

        vm.prank(naruto);
        feeContract.registerAsset(address(token), config);
    }

    function testUpdateAssetFeeConfigRevertsWhenCalledByNonOwner() public {
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
        feeContract.updateAssetFeeConfig(address(token), config);
        vm.stopPrank();
    }

    function testUpdateAssetFeeConfigRevertsIfAssetIsZero() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            feeRecipient: feeRecipient
        });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.updateAssetFeeConfig(address(0), config);
        vm.stopPrank();
    }

    function testUpdateAssetFeeConfigRevertsIfAssetNotRegistered() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.deregisterAsset(address(token));

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.updateAssetFeeConfig(address(token), config);
        vm.stopPrank();
    }

    function testUpdateAssetFeeConfigRevertsWhenConfigHasFeeRecipientAsZeroAddress() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 10e6});

        IVariableVaultFee.AssetFeeConfig memory invalidConfig =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee,
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: address(0)
            });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAssetConfig.selector);
        feeContract.updateAssetFeeConfig(address(token), invalidConfig);
        vm.stopPrank();
    }

    function testUpdateAssetFeeConfigRevertsOnExceedingMaxPercentage() public {
        // This exceeds MAX_PERCENTAGE_FEE(5e16)
        uint256 excessive = 1e18;

        IVariableVaultFee.FeeConfig memory invalidPercentage =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: excessive});

        IVariableVaultFee.AssetFeeConfig memory invalidConfig = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: invalidPercentage,
            depositFee: invalidPercentage,
            instantWithdrawalFee: invalidPercentage,
            flashRedeemFee: invalidPercentage,
            feeRecipient: feeRecipient
        });

        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAssetConfig.selector);
        feeContract.updateAssetFeeConfig(address(token), invalidConfig);
        vm.stopPrank();
    }

    function testUpdateAssetFeeConfigSuccessfullyUpdatesFee() public {
        (
            IVariableVaultFee.FeeConfig memory owithdrawFee,
            IVariableVaultFee.FeeConfig memory odepositFee,
            IVariableVaultFee.FeeConfig memory oinstantWithdrawalFee,
            IVariableVaultFee.FeeConfig memory oflashRedeemFee,
            address orecipient
        ) = feeContract.assetFee(address(token));

        IVariableVaultFee.AssetFeeConfig memory oldConfig =
            IVariableVaultFee.AssetFeeConfig(odepositFee, owithdrawFee, oinstantWithdrawalFee, oflashRedeemFee, orecipient);

        IVariableVaultFee.FeeConfig memory dNewFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 3e15 // 0.3%
        });
        IVariableVaultFee.FeeConfig memory wNewFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 4e15 // 0.4%
        });
        IVariableVaultFee.FeeConfig memory iwNewFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 5e15 // 0.5%
        });
        IVariableVaultFee.FeeConfig memory frFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 6e15 // 0.6%
        });

        address newFeeRecipient = makeAddr("newAddr");

        IVariableVaultFee.AssetFeeConfig memory updatedConfig =
            IVariableVaultFee.AssetFeeConfig({
                depositFee: dNewFee,
                withdrawalFee: wNewFee,
                instantWithdrawalFee: iwNewFee,
                flashRedeemFee: frFee,
                feeRecipient: newFeeRecipient
            });

        vm.prank(naruto);

        vm.expectEmit(true, true, true, true);
        emit IVariableVaultFee.UpdateAssetFeeConfig(naruto, address(token), oldConfig, updatedConfig);

        feeContract.updateAssetFeeConfig(address(token), updatedConfig);

        (
            IVariableVaultFee.FeeConfig memory withdrawFee,
            IVariableVaultFee.FeeConfig memory depositFee,
            IVariableVaultFee.FeeConfig memory instantWithdrawalFee,
            IVariableVaultFee.FeeConfig memory flashRedeemFee,
            address recipient
        ) = feeContract.assetFee(address(token));

        assertEq(uint8(depositFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(depositFee.feeAmount, 3e15, "deposit fee mismatch");

        assertEq(uint8(withdrawFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(withdrawFee.feeAmount, 4e15, "withdrawal fee mismatch");

        assertEq(uint8(instantWithdrawalFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(instantWithdrawalFee.feeAmount, 5e15, "instant withdrawal fee mismatch");

        assertEq(uint8(flashRedeemFee.feeType), uint8(IVariableVaultFee.FeeType.PERCENTAGE));
        assertEq(flashRedeemFee.feeAmount, 6e15, "instant withdrawal fee mismatch");


        assertEq(recipient, newFeeRecipient);
    }
}
