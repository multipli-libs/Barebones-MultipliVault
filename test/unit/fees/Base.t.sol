// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {BaseNetworkTokenConfig} from "test/BaseNetworkTokenConfig.t.sol";

contract FeeBase is Test, BaseNetworkTokenConfig {
    address naruto;
    uint256 narutoPrivKey;
    address madara;
    uint256 madaraPrivKey;
    address feeRecipient;

    MockERC20 token;

    VariableVaultFee feeContract;

    function setUp() public virtual {
        super.setTokenNetworkConfig();
        (naruto, narutoPrivKey) = makeAddrAndKey("naruto");
        (madara, madaraPrivKey) = makeAddrAndKey("madara");
        feeRecipient = makeAddr("sakura");
        feeContract = new VariableVaultFee(naruto);
        token = new MockERC20(config.tokenConfig.name, config.tokenConfig.assetSymbol, config.tokenConfig.decimals);

        vm.label({account: address(token), newLabel: config.tokenConfig.assetSymbol});
    }
}
