// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestRedeem is BaseTest {
    using Math for uint256;

    uint256 internal aliceShares = 100 * 1e6;

    function setUp() public override {
        BaseTest.setUp();
    }

    function testredeemReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.UseRequestRedeem.selector));
        depositVault.redeem(aliceShares, users.alice, users.alice);
    }
}
