// SPDX-License-Identifier: MIT


pragma solidity 0.8.34;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "./Base.t.sol";

import {Role} from "src/common/Role.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";


contract TestAdminBurn is BaseTest {
    uint256 INITIAL_DEPOSIT_AMOUNT = getQuantizedValue(100);

    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank(users.alice);
        depositVault.deposit(INITIAL_DEPOSIT_AMOUNT, users.alice);
        vm.stopPrank();
    }

    function test__adminBurn__Reverts__CalledByUnAuthorizedUser() public {
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.adminBurn(users.alice, getQuantizedValue(10));
        vm.stopPrank();
    }

    function test__adminBurn__Reverts__ReceiverZeroAddress() public {
        vm.startPrank(users.admin);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSender(address)", address(0)));
        depositVault.adminBurn(address(0), getQuantizedValue(10));
        vm.stopPrank();
    }

    function test__adminBurn__Reverts__OwnerInsufficientBalance() public {
        address naruto = makeAddr("naruto");

        uint256 shares = getQuantizedValue(10);

        vm.startPrank(users.admin);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", naruto, 0, shares));
        depositVault.adminBurn(naruto, shares);
    }

    function test__adminBurn__Success__SmallAmount() public {
        uint256 shares = 1;

        uint256 aliceVaultBalance = depositVault.balanceOf(users.alice);
        uint256 totalVaultSupply = depositVault.totalSupply();

        assertNotEq(aliceVaultBalance, 0); // verify balance is not 0

        vm.startPrank(users.admin);
        depositVault.adminBurn(users.alice, shares);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), aliceVaultBalance - shares, "alice share mismatch");
        assertEq(depositVault.totalSupply(), totalVaultSupply - shares, "total supply mismatch");

    }

    function test__adminBurn__Success__HALF_AMOUNT() public {
        uint256 shares = depositVault.balanceOf(users.alice) / 2;

        uint256 aliceVaultBalance = depositVault.balanceOf(users.alice);
        uint256 totalVaultSupply = depositVault.totalSupply();

        assertNotEq(aliceVaultBalance, 0); // verify balance is not 0

        vm.startPrank(users.admin);
        depositVault.adminBurn(users.alice, shares);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), aliceVaultBalance - shares, "alice share mismatch");
        assertEq(depositVault.totalSupply(), totalVaultSupply - shares, "total supply mismatch");

    }

    function test__adminBurn__Success__FULL_AMOUNT() public {
        uint256 shares = depositVault.balanceOf(users.alice);

        uint256 aliceVaultBalance = depositVault.balanceOf(users.alice);
        uint256 totalVaultSupply = depositVault.totalSupply();

        assertNotEq(aliceVaultBalance, 0); // verify balance is not 0

        vm.startPrank(users.admin);
        depositVault.adminBurn(users.alice, shares);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), 0, "alice share mismatch");
        assertEq(depositVault.totalSupply(), totalVaultSupply - shares, "total supply mismatch");

    }

    function test__adminBurn__Success_WithPermissionedUser(uint256 burnAmt) public {
        uint256 shares = depositVault.balanceOf(users.alice);

        burnAmt = bound(burnAmt, 0, shares);

        //=== Assign permission to naruto to call adminBurn

        // create naruto user
        (address naruto, uint256 narutoPriv) = makeAddrAndKey("naruto");

        RolesAuthority rAuthority = RolesAuthority(address(authority));

        // assign permission to naruto to call adminBurn method
        vm.startPrank(users.admin);
        rAuthority.setUserRole(naruto, uint8(Role.ADMIN), true);
        rAuthority.setRoleCapability(uint8(Role.ADMIN), address(depositVault), depositVault.adminBurn.selector, true);
        vm.stopPrank();
        // ==================================

        // burn alice shares
        vm.startPrank(naruto);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(users.alice, address(0), shares);
        depositVault.adminBurn(users.alice, shares);
        vm.stopPrank();

        // ensure alice has 0 balance
        assertEq(depositVault.balanceOf(users.alice), 0, "balance mismatch");

    }

}