// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract FeeBase is Test {
    address naruto;
    uint256 narutoPrivKey;
    address madara;
    uint256 madaraPrivKey;
    address feeRecipient;

    MockERC20 USDC;

    VariableVaultFee feeContract;

    function setUp() public virtual {
        (naruto, narutoPrivKey) = makeAddrAndKey("naruto");
        (madara, madaraPrivKey) = makeAddrAndKey("madara");
        feeRecipient = makeAddr("sakura");
        feeContract = new VariableVaultFee(naruto);
        USDC = new MockERC20("USDC", "USDC");

        vm.label({account: address(USDC), newLabel: "USDC"});
    }
}
