// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {MockMultipliVaultV2} from "../../mocks/MockMultipliVaultV2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";




contract TestUpgradeToAndCall is BaseTest {
    address newImplementation;

    function setUp() public override {
        super.setUp();
    }

    function test_upgradeToAndCall_SuccessWhenCalledByAdmin () public {
        vm.startPrank(users.admin);
        Upgrades.upgradeProxy(
            address(depositVault),
            "MockMultipliVaultV2.sol",
            ""
        );
        vm.stopPrank();

        string memory response = MockMultipliVaultV2(address(depositVault)).newMethod();
        assertEq(response, "new method");
    }

    function test_upgradeToAndCall_SuccessWhenCalledByAuthorizedUser () public {
        // assign permission to alice to call upgradeProxy
        uint8 UPGRADER_ROLE = 10;
        vm.startPrank(users.admin);
        RolesAuthority(address(authority)).setUserRole(users.alice, UPGRADER_ROLE, true);
        RolesAuthority(address(authority)).setRoleCapability(UPGRADER_ROLE, address(depositVault), depositVault.upgradeToAndCall.selector, true);
        vm.stopPrank();

        vm.startPrank(users.alice);
        Upgrades.upgradeProxy(
            address(depositVault),
            "MockMultipliVaultV2.sol",
            ""
        );
        vm.stopPrank();

        string memory response = MockMultipliVaultV2(address(depositVault)).newMethod();
        assertEq(response, "new method");
    }

    function test_upgradeToAndCall_FailsWhenCalledByUnAuthorizedUser () public {
        vm.startPrank(users.alice);
        address newImpl = address(new MockMultipliVaultV2());
        vm.expectRevert("UNAUTHORIZED");
        depositVault.upgradeToAndCall(newImpl, "");
        vm.stopPrank();
    }
}