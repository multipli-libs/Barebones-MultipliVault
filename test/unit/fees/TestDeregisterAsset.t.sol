// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestDeregisterAsset is FeeBase {
    function testDeregisterAssetRevertsWhenCalledByNonOwner() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)});

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

        vm.prank(madara);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, madara));
        feeContract.deregisterAsset(address(token));
    }

    function testDeregisterAssetRevertsIfAssetNotRegistered() public {
        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.deregisterAsset(address(token));
    }

    function testDeregisterAssetRevertsIfZeroAddress() public {
        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.deregisterAsset(address(0));
    }

    function testDeregisterAssetSuccessfullyRemovesAsset() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)});

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

        vm.prank(naruto);
        feeContract.deregisterAsset(address(token));

        assertEq(feeContract.isAssetRegistered(address(token)), false);
    }
}
