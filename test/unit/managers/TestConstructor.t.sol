// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract TestConstructor is VaultFundManagerBase {
    function test_Constructor_RevertsWithZeroAddress() public {
        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        new VaultFundManager(payable(address(0)));
    }

    function test_Constructor_SetsVaultCorrectly() public view {
        assertEq(address(fundManager.vault()), address(vault));
    }

    function test_Constructor_SetsAssetCorrectly() public view {
        assertEq(fundManager.asset(), address(token));
    }

    function test_Constructor_SetsImmutableVariables() public {
        // Deploy a new fund manager to test constructor
        VaultFundManager newFundManager = new VaultFundManager(payable(address(vault)));

        // Verify immutable variables are set correctly
        assertEq(address(newFundManager.vault()), address(vault));
        assertEq(newFundManager.asset(), address(token));
    }

    function test_Constructor_WithValidVaultAddress() public {
        vm.startPrank(users.admin);
        bytes memory data =
            abi.encodeWithSelector(MultipliVault.initialize.selector, token, users.admin, "New Vault", "NV");

        address newProxy = Upgrades.deployUUPSProxy("MultipliVault.sol", data);
        MultipliVault newVaultProxy = MultipliVault(payable(address(newProxy)));

        // Deploy fund manager with new vault
        VaultFundManager newFundManager = new VaultFundManager(payable(address(newVaultProxy)));

        // Verify the fund manager is correctly initialized
        assertEq(address(newFundManager.vault()), address(newVaultProxy));
        assertEq(newFundManager.asset(), address(token));

        vm.stopPrank();
    }

    function test_Constructor_LabelsAreSet() public view {
        // Verify that our labels are correctly set in the base setup
        // This is more of a sanity check for our test setup
        assertTrue(address(fundManager.vault()) != address(0));
        assertTrue(fundManager.asset() != address(0));
    }
}
