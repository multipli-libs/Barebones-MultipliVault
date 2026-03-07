// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";

contract Unpause_Unit_Concrete_Test is BaseTest {
    function setUp() public override {
        BaseTest.setUp();

        vm.startPrank({msgSender: users.admin});
        depositVault.pause();
        assertTrue(depositVault.paused(), "Vault was not paused.");
    }

    function testUnpauseIsuccess() public {
        depositVault.unpause();
        assertFalse(depositVault.paused(), "Vault was not unpaused.");
    }

    function testUnpause__RevertsWhenCalledUnauthorizedUser() public {
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSignature("AuthUpgradeable__Unauthorized()"));
        depositVault.unpause();
    }
}
