// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";

import {Errors} from "src/libraries/Errors.sol";

import {IMultipliVault} from "src/interfaces/IMultipliVault.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

contract TestUpdateMinDepositAmount is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
    }

    function test_updateMinDepositAmount__Reverts_onAuthorizedUserAccess() public {
        assertEq(depositVault.minDepositAmount(), 0, "Initial sanity check failed");

        vm.expectRevert("UNAUTHORIZED");
        depositVault.updateMinDepositAmount(getQuantizedValue(10));
    }

    function test_updateminDepositAmount__Success_onAdminUserAccess() public {
        assertEq(depositVault.minDepositAmount(), 0, "Initial sanity check failed");

        vm.startPrank(users.admin);

        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.MinDepositAmountUpdated(0, getQuantizedValue(10));
        depositVault.updateMinDepositAmount(getQuantizedValue(10));
        vm.stopPrank();

        assertEq(depositVault.minDepositAmount(), getQuantizedValue(10), "minDepositAmount is not updated");
    }

    function test_updateMinDepositAmount__Success_onAuthorizedUserAccess() public {
        assertEq(depositVault.minDepositAmount(), 0, "Initial sanity check failed");

        // Assign `SECONDARY_ADMIN_USER` to Alice
        // Grant `SECONDARY_ADMIN_USER` to call `updateMinDepositAmount` method
        uint8 SECONDARY_ADMIN_USER = 2;
        address authorityAddress = address(depositVault.authority());

        vm.startPrank(users.admin);
        MockAuthority(address(authorityAddress)).setUserRole(address(users.alice), SECONDARY_ADMIN_USER, true);
        MockAuthority(address(authorityAddress)).setRoleCapability(
            SECONDARY_ADMIN_USER, address(depositVault), MultipliVault.updateMinDepositAmount.selector, true
        );
        vm.stopPrank();

        // update `MinDepositAmountUpdated` using `SECONDARY_ADMIN_USER`
        vm.startPrank(users.alice);

        vm.expectEmit(true, true, true, true);
        emit IMultipliVault.MinDepositAmountUpdated(0, getQuantizedValue(10));
        depositVault.updateMinDepositAmount(getQuantizedValue(10));

        vm.stopPrank();

        assertEq(depositVault.minDepositAmount(), getQuantizedValue(10), "minDepositAmount is not updated");
    }
}
