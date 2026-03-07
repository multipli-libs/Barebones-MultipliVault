// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";

contract TestPause is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
    }

    function testPauseSuccess() public {
        vm.startPrank({msgSender: users.admin});
        depositVault.pause();
        assertTrue(depositVault.paused(), "Vault was not paused.");
    }

    function testPause__RevertsWhenCalledByNonAuthorizedUser() public {
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.pause();
    }
}
