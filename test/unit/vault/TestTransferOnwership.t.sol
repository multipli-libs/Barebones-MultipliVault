// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";

/// @notice Base test contract with common logic needed by all tests.

contract TransferOwnership_Unit_Concrete_Test is BaseTest {
    // ====================================== TEST CONTRACTS =======================================

    // ====================================== SET-UP FUNCTION ======================================
    function setUp() public override {
        super.setUp();
    }

    function testTransferOwnership() public {
        vm.startPrank({msgSender: users.admin});
        depositVault.transferOwnership(users.bob);
        assertEq(depositVault.owner(), users.bob);
    }
}
