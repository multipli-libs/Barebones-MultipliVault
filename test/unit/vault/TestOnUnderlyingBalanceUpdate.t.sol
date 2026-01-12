// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract OnUnderlyingBalanceUpdate_Unit_Concrete_Test is BaseTest {
    using Math for uint256;

    function setUp() public override {
        BaseTest.setUp();
        vm.startPrank({msgSender: users.alice});
    }

    function testOnUnderlyingBalanceUpdateIsSuccess() public {
        uint256 amount = 100 * getQuantizedValue(1);
        depositVault.deposit(amount, users.alice);

        vm.startPrank({msgSender: users.admin});

        uint256 currentPricePerShare = depositVault.totalAssets().mulDiv(DENOMINATOR, depositVault.totalSupply());

        uint256 newUnderlyingBalance = 0;
        depositVault.onUnderlyingBalanceUpdate(newUnderlyingBalance);

        assertEq(currentPricePerShare, depositVault.lastPricePerShare(), "price per share should not change");
    }

    function test_onUnderlyingBalanceUpdateFailsAndContractIsPausedWhenPercentageChangeGreaterThanMaxPercentageChange()
        public
    {
        uint256 amount = 100 * getQuantizedValue(1);
        depositVault.deposit(amount, users.alice);

        vm.startPrank({msgSender: users.admin});
        bool pausedBefore = depositVault.paused();
        assertFalse(pausedBefore, "vault should not be paused");
        depositVault.onUnderlyingBalanceUpdate(0);

        vm.roll(block.number + 1);
        uint256 newUnderlyingBalance = getQuantizedValue(101)/ 100; // more than 1% difference
        depositVault.onUnderlyingBalanceUpdate(newUnderlyingBalance);
        bool pausedAfter = depositVault.paused();

        assertTrue(pausedAfter, "vault should be paused");
    }

    function test_onUnderlyingBalanceUpdate__RevertsWhenCalledByUnauthorizationUser() public {
        uint256 amount = 100 * getQuantizedValue(1);
        depositVault.deposit(amount, users.alice);

        vm.expectRevert("UNAUTHORIZED");
        depositVault.onUnderlyingBalanceUpdate(0);
    }

    function test_onUnderlyingBalanceUpdate__RevertsWhenCalledWithinSameBlock() public {
        uint256 amount = 100 * getQuantizedValue(1);
        depositVault.deposit(amount, users.alice);

        vm.stopPrank();
        vm.startPrank({msgSender: users.admin});
        depositVault.onUnderlyingBalanceUpdate(getQuantizedValue(1));
        vm.expectRevert(abi.encodeWithSelector(Errors.UpdateAlreadyCompletedInThisBlock.selector));
        depositVault.onUnderlyingBalanceUpdate(getQuantizedValue(1));
    }
}
