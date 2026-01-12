// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

/// @notice Base test contract with common logic needed by all tests.

contract TestIsAuthorized is BaseTest {
    // ====================================== TEST CONTRACTS =======================================

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public override {
        super.setUp();
    }

    function testIsAuthorizedForAdmin() public {
        vm.startPrank({msgSender: users.admin});

        bool res = depositVault.isAuthorized(users.admin, msg.sig);
        assertTrue(res);
    }

    function testIsAuthorizedForUnAuthorizedUser() public {
        bool res = depositVault.isAuthorized(users.alice, MultipliVault.pause.selector);
        assertFalse(res);
    }

    function testIsAuthorizedForAuthorizedUser() public {
        vm.startPrank({msgSender: users.admin});
        Authority authority = depositVault.authority();
        MockAuthority(address(authority)).setUserRole(users.alice, ADMIN_ROLE, true);
        MockAuthority(address(authority)).setRoleCapability(
            ADMIN_ROLE, address(depositVault), MultipliVault.pause.selector, true
        );
        vm.stopPrank();

        bool res = depositVault.isAuthorized(users.alice, MultipliVault.pause.selector);
        assertTrue(res);
    }
}
