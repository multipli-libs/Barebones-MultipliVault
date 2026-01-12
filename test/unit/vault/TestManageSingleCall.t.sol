// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Errors} from "src/libraries/Errors.sol";

import {BaseTest} from "./Base.t.sol";
import {MockTarget} from "../../mocks/MockTarget.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";

contract ManageSingleCall_Unit_Concrete_Test is BaseTest {
    uint256 internal value = 1 ether;
    address internal mockTarget;
    bytes4 internal targetfunctionSig = MockTarget.someFunction.selector;
    bytes internal data = abi.encodeWithSelector(MockTarget.someFunction.selector, uint256(42));

    function setUp() public override {
        BaseTest.setUp();

        vm.deal(address(depositVault), value); // Fund the vault with native assets

        mockTarget = address(new MockTarget());

        vm.startPrank({msgSender: users.admin});
        MockAuthority(address(depositVault.authority())).setRoleCapability(
            ADMIN_ROLE, mockTarget, targetfunctionSig, true
        );
    }

    function test_ManageSingleCall_Success() public {
        depositVault.manage(mockTarget, data, value);
        uint256 result = MockTarget(mockTarget).value();
        assertEq(result, 42, "Function was not called correctly.");
    }

    function test_ManageSingleCall_RevertOnUnauthorizedUser() public {
        vm.startPrank({msgSender: users.bob}); // Stop acting as the owner
        vm.expectRevert("UNAUTHORIZED");
        depositVault.manage(mockTarget, data, value);
    }

    function test_ManageSingleCall_RevertOnTargetMethodNotAuthorized() public {
        // Remove the capability
        MockAuthority(address(depositVault.authority())).setRoleCapability(
            ADMIN_ROLE, mockTarget, targetfunctionSig, false
        );
        vm.expectRevert(
            abi.encodeWithSelector(Errors.TargetMethodNotAuthorized.selector, mockTarget, targetfunctionSig)
        );
        depositVault.manage(mockTarget, data, value);
    }
}
