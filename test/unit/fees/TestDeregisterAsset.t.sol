// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestDeregisterAsset is FeeBase {
    function testDeregisterAssetRevertsWhenCalledByNonOwner() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee,
                depositFee: flatFee,
                instantWithdrawalFee: flatFee,
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.prank(madara);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, madara));
        feeContract.deregisterAsset(address(USDC));
    }

    function testDeregisterAssetRevertsIfAssetNotRegistered() public {
        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.deregisterAsset(address(USDC));
    }

    function testDeregisterAssetRevertsIfZeroAddress() public {
        vm.startPrank(naruto);
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.deregisterAsset(address(0));
    }

    function testDeregisterAssetSuccessfullyRemovesAsset() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee,
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.prank(naruto);
        feeContract.deregisterAsset(address(USDC));

        assertEq(feeContract.isAssetRegistered(address(USDC)), false);
    }
}
