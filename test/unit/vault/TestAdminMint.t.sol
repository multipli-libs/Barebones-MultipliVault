// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;



import {BaseTest} from "./Base.t.sol";
import {Role} from "src/common/Role.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";


contract TestAdminMint is BaseTest {
    uint256 INITIAL_DEPOSIT_AMOUNT = getQuantizedValue(100);

    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank(users.alice);
        depositVault.deposit(INITIAL_DEPOSIT_AMOUNT, users.alice);
        vm.stopPrank();
    }

    function test_adminMint__Reverts__CalledByUnAuthorizedUser() public {
        vm.startPrank(users.alice);
        vm.expectRevert("UNAUTHORIZED");
        depositVault.adminMint(users.alice, getQuantizedValue(10));
        vm.stopPrank();
    }

    function test_adminMint__Reverts__ReceiverZeroAddress() public {
        vm.startPrank(users.admin);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        depositVault.adminMint(address(0), getQuantizedValue(10));
        vm.stopPrank();
    }

    function test_adminMint__Success__SmallAmount() public {
        uint256 shares = 1;

        uint256 aliceVaultBalance = depositVault.balanceOf(users.alice);
        uint256 totalVaultSupply = depositVault.totalSupply();
        uint256 totalAssets = depositVault.totalAssets();

        assertNotEq(aliceVaultBalance, 0); // verify balance is not 0

        vm.startPrank(users.admin);
        depositVault.adminMint(users.alice, shares);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), aliceVaultBalance + shares, "alice share mismatch");
        assertEq(depositVault.totalSupply(), totalVaultSupply + shares, "total supply mismatch");
        assertEq(depositVault.totalAssets(), totalAssets, "total assets should not change");

    }

    function test_adminMint__Success__MediumAmount() public {
        uint256 shares = getQuantizedValue(100_000);

        uint256 aliceVaultBalance = depositVault.balanceOf(users.alice);
        uint256 totalVaultSupply = depositVault.totalSupply();
        uint256 totalAssets = depositVault.totalAssets();

        assertNotEq(aliceVaultBalance, 0); // verify balance is not 0

        vm.startPrank(users.admin);
        depositVault.adminMint(users.alice, shares);
        vm.stopPrank();

        assertEq(depositVault.balanceOf(users.alice), aliceVaultBalance + shares, "alice share mismatch");
        assertEq(depositVault.totalSupply(), totalVaultSupply + shares, "total supply mismatch");
        assertEq(depositVault.totalAssets(), totalAssets, "total assets should not change");

    }

    function test__adminMint__Success_WithPermissionedUser(uint256 mintAmt) public {
        uint256 aliceBalance = depositVault.balanceOf(users.alice);
        mintAmt = bound(mintAmt, 0, type(uint256).max - aliceBalance);

        //=== Assign permission to naruto to call adminMint

        RolesAuthority rAuthority = RolesAuthority(address(authority));

        // create naruto user
        (address naruto, uint256 narutoPriv) = makeAddrAndKey("naruto");

        // assign permission to naruto to call adminBurn method
        vm.startPrank(users.admin);
        rAuthority.setUserRole(naruto, uint8(Role.ADMIN), true);
        rAuthority.setRoleCapability(uint8(Role.ADMIN), address(depositVault), depositVault.adminMint.selector, true);
        vm.stopPrank();
        // ==================================

        // mint `mintAmt` to Alice
        vm.startPrank(naruto);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), users.alice, mintAmt);
        depositVault.adminMint(users.alice, mintAmt);
        vm.stopPrank();

        // ensure alice has 0 balance
        assertEq(depositVault.balanceOf(users.alice), aliceBalance + mintAmt, "balance mismatch");

    }



}