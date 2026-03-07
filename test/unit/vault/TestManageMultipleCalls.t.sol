// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Errors} from "src/libraries/Errors.sol";

import {BaseTest} from "./Base.t.sol";
import {MockTarget} from "../../mocks/MockTarget.sol";
import {MockAuthority} from "../../mocks/MockAuthority.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestManageMultipleCalls is BaseTest {
    uint256 internal value = 1 ether;
    address[] internal mockTargets;
    bytes4 internal targetfunctionSig = MockTarget.someFunction.selector;
    bytes internal data = abi.encodeWithSelector(MockTarget.someFunction.selector, uint256(42));

    function setUp() public override {
        BaseTest.setUp();

        vm.deal(address(depositVault), value); // Fund the vault with native assets

        mockTargets.push(address(new MockTarget()));
        mockTargets.push(address(new MockTarget()));

        vm.startPrank({msgSender: users.admin});

        for (uint256 i = 0; i < mockTargets.length; i++) {
            MockAuthority(address(depositVault.authority())).setRoleCapability(
                ADMIN_ROLE, mockTargets[i], targetfunctionSig, true
            );
        }
    }

    function testManageMultipleCallSuccess() public {
        _manage();
        for (uint256 i = 0; i < mockTargets.length; i++) {
            uint256 result = MockTarget(mockTargets[i]).value();
            assertEq(result, 42, "Function was not called correctly.");
        }
    }

    function testManageMultipleCall__RevertsOnUnauthorizedUser() public {
        vm.startPrank({msgSender: users.bob}); // Stop acting as the owner
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        _manage();
    }

    function testManageMultipleCall__RevertsOnTargetMethodNotAuthorized() public {
        // Remove the capability
        for (uint256 i = 0; i < mockTargets.length; i++) {
            MockAuthority(address(depositVault.authority())).setRoleCapability(
                ADMIN_ROLE, mockTargets[i], targetfunctionSig, false
            );
        }

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Errors__TargetMethodNotAuthorized.selector, mockTargets[0], targetfunctionSig)
        );
        _manage();
    }

    function testManageMultipleCall__Reverts_WhenArrayLengthsDontMatch() public {
        uint256 mockTargetsLength = mockTargets.length;

        bytes[] memory datas = new bytes[](mockTargets.length + 1);
        uint256[] memory values = new uint256[](mockTargets.length);
        vm.expectRevert(abi.encodeWithSignature("Errors__ArrayLengthsMismatch()"));
        // depositVault.manage(mockTargets, datas, values);
        _manage(mockTargets, datas, values);

        bytes[] memory datas1 = new bytes[](mockTargets.length);
        uint256[] memory values1 = new uint256[](mockTargets.length + 1);
        vm.expectRevert(abi.encodeWithSignature("Errors__ArrayLengthsMismatch()"));
        depositVault.manage(mockTargets, datas1, values1);

        address[] memory targets2;
        bytes[] memory datas2 = new bytes[](4);
        uint256[] memory values2 = new uint256[](4);
        vm.expectRevert(abi.encodeWithSignature("Errors__ArrayLengthsMismatch()"));
        depositVault.manage(targets2, datas2, values2);
    }

    function _manage(address[] memory targets, bytes[] memory datas, uint256[] memory values) internal {
        for (uint256 i=0; i < datas.length; i++) {
            datas[i] = data;
        }

        for (uint256 i=0; i < values.length; i++) {
            values[i] = 0;
        }

        depositVault.manage(targets, datas, values);

    }

    function _manage() internal {
        bytes[] memory datas = new bytes[](mockTargets.length);
        uint256[] memory values = new uint256[](mockTargets.length);
        for (uint256 i = 0; i < mockTargets.length; i++) {
            datas[i] = data;
            values[i] = 0;
        }

        depositVault.manage(mockTargets, datas, values);
    }
}