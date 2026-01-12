// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { VaultFundManager } from "src/managers/VaultFundManager.sol";
import { MockOperator } from "../../mocks/MockOperator.sol";
import { MockAuthority } from "../../mocks/MockAuthority.sol";
import { BaseTest } from "../vault/Base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUserOperatorWhitelist is BaseTest {
    address operatorOwner;
    uint256 operatorOwnerKey;

    VaultFundManager fundManager;
    MockOperator operator;

    uint256 INITIAL_OPERATOR_DEPOSIT_AMOUNT = 100e6;

    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank(users.admin);

        (operatorOwner, operatorOwnerKey) = makeAddrAndKey("operatorOwner");
        deal(operatorOwner, 10e18);
        deal(address(usdc), operatorOwner, 100_000e6);
        vm.label(operatorOwner, "operatorOwner");

        operator = new MockOperator();
        deal(address(operator), 10e18);
        deal(address(usdc), address(operator), 1_000_000e6);
        operator.setVault(depositVault);
        operator.mint(INITIAL_OPERATOR_DEPOSIT_AMOUNT);
        vm.label(address(operator), "operatorContract");

        fundManager = new VaultFundManager(payable(address(depositVault)));
        deal(address(usdc), address(fundManager), 1_000_000e6);

        MockAuthority(address(authority)).setRoleCapability(
            ADMIN_ROLE, address(fundManager), fundManager.updateUserOperatorWhitelist.selector, true
        );
        // Initial whitelist to allow setup verification
        _updatePermission(operatorOwner, address(operator), true);

        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    function _updatePermission(address user, address op, bool enabled) internal {
        vm.startPrank(users.admin);
        bytes memory data = abi.encodeWithSelector(
            fundManager.updateUserOperatorWhitelist.selector, user, op, enabled
        );
        depositVault.manage(address(fundManager), data, 0);
        vm.stopPrank();
    }

    function test_successfullyEnablesWhitelist() public {
        _updatePermission(operatorOwner, address(operator), true);

        assertTrue(
            fundManager.whitelistedUserOperator(operatorOwner, address(operator)),
            "Whitelist failed"
        );
    }

    function test_successfullyDisablesWhitelist() public {
        _updatePermission(operatorOwner, address(operator), true);
        _updatePermission(operatorOwner, address(operator), false);

        assertFalse(
            fundManager.whitelistedUserOperator(operatorOwner, address(operator)), "Disable failed"
        );
    }

    function test_revertsWhitelistIfNotCalledByVault() public {
        vm.expectRevert(VaultFundManager.UnauthorizedCaller.selector);
        fundManager.updateUserOperatorWhitelist(operatorOwner, address(operator), true);
    }

    function test_revertsWhitelistIfZeroUser() public {
        vm.startPrank(users.admin);

        bytes memory data = abi.encodeWithSelector(
            fundManager.updateUserOperatorWhitelist.selector, address(0), address(operator), true
        );

        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        depositVault.manage(address(fundManager), data, 0);
        vm.stopPrank();
    }

    function test_revertsWhitelistIfZeroOperator() public {
        vm.startPrank(users.admin);
        bytes memory data = abi.encodeWithSelector(
            fundManager.updateUserOperatorWhitelist.selector, operatorOwner, address(0), true
        );

        vm.expectRevert(VaultFundManager.ZeroAddress.selector);
        depositVault.manage(address(fundManager), data, 0);
        vm.stopPrank();
    }

    function test_multipleOperatorsCanBeWhitelisted() public {
        // First additional operator-owner pair
        (address operatorOwner2,) = makeAddrAndKey("operatorOwner2");
        MockOperator operator2 = new MockOperator();
        operator2.setVault(depositVault);
        _updatePermission(operatorOwner2, address(operator2), true);

        // Second additional operator-owner pair
        (address operatorOwner3,) = makeAddrAndKey("operatorOwner3");
        MockOperator operator3 = new MockOperator();
        operator3.setVault(depositVault);
        _updatePermission(operatorOwner3, address(operator3), true);

        // Assert both are correctly whitelisted
        assertTrue(
            fundManager.whitelistedUserOperator(operatorOwner2, address(operator2)),
            "Operator 2 not whitelisted"
        );

        assertTrue(
            fundManager.whitelistedUserOperator(operatorOwner3, address(operator3)),
            "Operator 3 not whitelisted"
        );
    }

    function test_emitsWhitelistUpdateEventCorrectly() public {
        vm.expectEmit(true, true, true, true);
        emit VaultFundManager.UpdateOperatorWhitelist(operatorOwner, address(operator), true);

        _updatePermission(operatorOwner, address(operator), true);
    }

    function test_revertsIfNonAdminTriesToCallManage() public {
        address badUser = makeAddr("badUser");
        vm.startPrank(badUser); // Simulate bad user

        bytes memory data = abi.encodeWithSelector(
            fundManager.updateUserOperatorWhitelist.selector, operatorOwner, address(operator), true
        );

        // Expect revert because `badUser` does not have permission to call manage on the vault
        vm.expectRevert("UNAUTHORIZED");
        depositVault.manage(address(fundManager), data, 0);
        vm.stopPrank();
    }
}
