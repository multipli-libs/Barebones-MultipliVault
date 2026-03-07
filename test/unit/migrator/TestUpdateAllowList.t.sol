// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MigratorBaseTest} from "./Base.t.sol";
import {MultipliMigrator} from "src/migrator/MultipliMigrator.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";

contract TestUpdateAllowList is MigratorBaseTest {    
    function test__updateAllowList__Reverts__CalledByNonOwner() public {
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.alice));
        migrator.updateAllowList(users.bob, true);
        vm.stopPrank();
    }

    function test__updateAllowList__Reverts__InvalidAddress() public {
        vm.startPrank(users.admin);
        vm.expectRevert(MultipliMigrator.MultipliMigrator__InvalidAddress.selector);
        migrator.updateAllowList(address(0), true);
        vm.stopPrank();
    }

    function test__updateAllowList__Success__EnableUser() public {
        assertFalse(migrator.allowList(users.alice), "alice should not be in allowlist initially");

        vm.startPrank(users.admin);
        vm.expectEmit(true, true, false, false);
        emit MultipliMigrator.UpdateAllowList(users.alice, true);
        migrator.updateAllowList(users.alice, true);
        vm.stopPrank();

        assertTrue(migrator.allowList(users.alice), "alice should be in allowlist");
    }

    function test__updateAllowList__Success__DisableUser() public {
        // First enable the user
        vm.startPrank(users.admin);
        migrator.updateAllowList(users.alice, true);
        vm.stopPrank();

        assertTrue(migrator.allowList(users.alice), "alice should be in allowlist");

        // Now disable the user
        vm.startPrank(users.admin);
        vm.expectEmit(true, true, false, false);
        emit MultipliMigrator.UpdateAllowList(users.alice, false);
        migrator.updateAllowList(users.alice, false);
        vm.stopPrank();

        assertFalse(migrator.allowList(users.alice), "alice should not be in allowlist");
    }

    function test__updateAllowList__Success__NoStateChange() public {
        assertFalse(migrator.allowList(users.alice), "alice should not be in allowlist initially");

        // Try to set same state (false -> false)
        vm.startPrank(users.admin);
        // Should not emit event when no state change
        vm.recordLogs();
        migrator.updateAllowList(users.alice, false);
        vm.stopPrank();

        assertFalse(migrator.allowList(users.alice), "alice should still not be in allowlist");
        
        // Verify no event was emitted
        // Note: This test assumes the function doesn't emit events when no state change occurs
        // based on the condition `if(allowList[user] != enable)` in the contract
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "no events should be emitted");
    }

    function test__updateAllowList__Success__MultipleUsers() public {
        address[] memory users_array = new address[](3);
        users_array[0] = users.alice;
        users_array[1] = users.bob;
        users_array[2] = operator;

        vm.startPrank(users.admin);
        
        // Enable all users
        for (uint256 i = 0; i < users_array.length; i++) {
            migrator.updateAllowList(users_array[i], true);
            assertTrue(migrator.allowList(users_array[i]), "user should be in allowlist");
        }

        // Disable all users
        for (uint256 i = 0; i < users_array.length; i++) {
            migrator.updateAllowList(users_array[i], false);
            assertFalse(migrator.allowList(users_array[i]), "user should not be in allowlist");
        }

        vm.stopPrank();
    }

    function testFuzz__updateAllowList__Success(address user, bool enable) public {
        vm.assume(user != address(0));
        
        vm.startPrank(users.admin);
        migrator.updateAllowList(user, enable);
        vm.stopPrank();

        assertEq(migrator.allowList(user), enable, "allowlist state mismatch");
    }
}