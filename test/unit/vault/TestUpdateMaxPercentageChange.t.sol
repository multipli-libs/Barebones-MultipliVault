// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";

import {Errors} from "src/libraries/Errors.sol";

contract TestUpdateMaxPercentageChange is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
        vm.startPrank({msgSender: users.admin});
    }

    function testUpdateMaxPercentageChangeIsSuccess() public {
        assertEq(depositVault.maxPercentageChange(), 1e16, "Initial sanity check failed");

        depositVault.updateMaxPercentageChange(2e16);
        assertEq(depositVault.maxPercentageChange(), 2e16, "percentage change was not updated.");
    }

    function testUpdateMaxPercentageChange__RevertsIfNewValueIsGreaterThanMaxThreshold() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.Errors__InvalidMaxPercentage.selector));
        depositVault.updateMaxPercentageChange(MAX_PERCENTAGE_THRESHOLD);
    }

    function testUpdateMaxPercentageChange__RevertsWhenCalledByNotAuthorizedUser() public {
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.updateMaxPercentageChange(1e16);
    }
}
