// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Withdraw_Unit_Concrete_Test is BaseTest {
    using Math for uint256;

    uint256 internal amount;

    function setUp() public override {
        BaseTest.setUp();
        amount = 100 * getQuantizedValue(1);
        vm.startPrank({msgSender: users.alice});
    }

    function testWithdrawReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.UseRequestRedeem.selector));
        depositVault.withdraw(amount, users.alice, users.alice);
    }
}
