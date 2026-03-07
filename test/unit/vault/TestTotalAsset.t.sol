// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseTest} from "./Base.t.sol";

contract TotalAssets_Unit_Concrete_Test is BaseTest {
    function setUp() public override {
        BaseTest.setUp();
        vm.startPrank({msgSender: users.alice});
    }

    function test_totalAssets_success() public {
        uint256 amount = 100 * getQuantizedValue(1);

        uint256 totalAssetsBefore = depositVault.totalAssets();
        assertTrue(totalAssetsBefore == 0, "Total assets before is not 0");

        token.transfer(address(depositVault), amount);

        uint256 totalAssetsAfter = depositVault.totalAssets();
        assertTrue(totalAssetsAfter == amount, "Total assets after is not the amount");
    }
}
