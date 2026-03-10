// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";
import {AuthUpgradeable} from "src/base/AuthUpgradeable.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";
import {Authority} from "@solmate/auth/Auth.sol";

/// @notice Base test contract with common logic needed by all tests.

contract TestSetAuthority is BaseTest {
    // ====================================== TEST CONTRACTS =======================================

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public override {
        super.setUp();
    }

    function test_setAuthority() public {
        vm.startPrank({msgSender: users.admin});

        uint8 NEWROLE = 2;

        // Update the existing authority to allow Bob to call `setAuthority` method
        MockAuthority(address(authority)).setUserRole(users.bob, NEWROLE, true);
        MockAuthority(address(depositVault.authority())).setRoleCapability(
            NEWROLE, address(depositVault), depositVault.setAuthority.selector, true
        );

        // Change Authority to a new authority
        MockAuthority newAuthority = new MockAuthority(users.bob, authority);
        vm.startPrank({msgSender: users.bob});
        depositVault.setAuthority(newAuthority);
        assertEq(address(depositVault.authority()), address(newAuthority));
    }

    function test_setAuthority_revertsWhenAuthorized() public {
        MockAuthority newAuthority = new MockAuthority(users.bob, authority);
        vm.startPrank({msgSender: users.bob});
        vm.expectRevert();
        depositVault.setAuthority(newAuthority);
        assertFalse(address(depositVault.authority()) == address(newAuthority));
        assertTrue(address(depositVault.authority()) == address(authority));
    }

    function test_setAuthority_revertsWhenAuthorityUnsetAndCallerIsNotOwner() public {
        vm.startPrank({msgSender: users.admin});
        depositVault.setAuthority(Authority(address(0)));

        MockAuthority newAuthority = new MockAuthority(users.bob, authority);

        vm.startPrank({msgSender: users.bob});
        vm.expectRevert(AuthUpgradeable.AuthUpgradeable__Unauthorized.selector);
        depositVault.setAuthority(newAuthority);

        assertEq(address(depositVault.authority()), address(0));
    }
}
