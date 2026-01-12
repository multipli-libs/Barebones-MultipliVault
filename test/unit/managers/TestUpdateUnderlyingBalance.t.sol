// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;


import {VaultFundManagerBase} from "./VaultFundManagerBase.t.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";
import {VaultFundManager} from "src/managers/VaultFundManager.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";

import { Errors } from "src/libraries/Errors.sol";


contract TestUpdateUnderlyingBalance is VaultFundManagerBase {
    RolesAuthority public rAuthority;

    function setUp() override public {
        VaultFundManagerBase.setUp();

        vm.startPrank(users.admin);
    
        // perform initial deposit by admin
        token.approve(address(vault), 100e6);
        vault.deposit(100e6, users.admin);

        rAuthority = RolesAuthority(address(authority));

        // users in `FUND_MANAGER_ROLE` role do not have permission to call `updateUnderlyingBalance`
        rAuthority.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), fundManager.updateUnderlyingBalance.selector, false
        );
        vm.stopPrank();
    }

    function assignPermission(address user) public {
        vm.startPrank(users.admin);

        rAuthority.setUserRole(user, FUND_MANAGER_ROLE, true);
        rAuthority.setRoleCapability(
            FUND_MANAGER_ROLE, address(fundManager), fundManager.updateUnderlyingBalance.selector, true
        );

        vm.stopPrank();
    }

    function test__updateUnderlyingBalance__RevertsWhenCalledByNonVaultAddress() public {
        vm.startPrank(users.admin);
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.updateUnderlyingBalance(0, 0);
    }

    function test__updateUnderlyingBalance__RevertsWhenCalledByUserAuthorizedToCallManagedButNotUpdateUnderlyingBalance() public {

        address user = users.alice;
        bytes4 manageSignature = bytes4(keccak256("manage(address,bytes,uint256)"));
        bytes4 updateUnderlyingBalanceSignature = bytes4(VaultFundManager.updateUnderlyingBalance.selector);
        address target = address(fundManager);
        bytes memory data = abi.encodeWithSelector(VaultFundManager.updateUnderlyingBalance.selector, 0, 0);


        // verify Alice can call manage
        assertTrue(rAuthority.canCall(user, address(vault), manageSignature), "alice cannot call `manage(address,bytes,uint256)`");
        assertFalse(rAuthority.canCall(user, address(fundManager), updateUnderlyingBalanceSignature), "alice can call `updateUnderlyingBalance(uint256,uint256)`");

        
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetMethodNotAuthorized.selector, address(fundManager), updateUnderlyingBalanceSignature));
        vault.manage(target, data, 0);

        vm.stopPrank();
    }

    function test__updateUnderlyingBalance__RevertsWhenOldAggBalanceDoesNotMatchVaultAggBalance() public {
        assignPermission(users.alice);

        uint256 currentBalance = vault.aggregatedUnderlyingBalances();

        uint256 oldBalance = currentBalance + 1; // incorrect balance
        uint256 newBalance = currentBalance + 3; // increase the updated blaance by 3

        address user = users.alice;
        address target = address(fundManager);
        bytes memory data = abi.encodeWithSelector(VaultFundManager.updateUnderlyingBalance.selector, oldBalance, newBalance);

        vm.startPrank(user);
        vm.expectRevert(VaultFundManager.AggregatedBalanceMismatch.selector);
        vault.manage(target, data, 0);
        vm.stopPrank();

    }

    function test__updateUnderlyingBalance__IsSuccess() public {
        assignPermission(users.alice);

        uint256 currentBalance = vault.aggregatedUnderlyingBalances();

        uint256 oldBalance = currentBalance; // incorrect balance
        uint256 newBalance = currentBalance + 3; // increase the updated blaance by 3

        address user = users.alice;
        address target = address(fundManager);
        bytes memory data = abi.encodeWithSelector(VaultFundManager.updateUnderlyingBalance.selector, oldBalance, newBalance);

        vm.startPrank(user);
        vault.manage(target, data, 0);
        vm.stopPrank();

        assertEq(vault.aggregatedUnderlyingBalances(), newBalance, "underlying balance not updated");

    }

}
