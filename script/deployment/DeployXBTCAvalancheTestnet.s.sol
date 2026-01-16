// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {BaseWithSharedConfig} from "./common/BaseWithSharedConfig.s.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {console} from "forge-std/Script.sol";


contract DeployXBTCAvalancheTestnet is BaseWithSharedConfig {
    function createBTC(address initialRecipient, uint256 initialRecipientAmount) internal returns (address) {
        MockERC20 btcToken = new MockERC20("Bitcoin", "BTC.b", 8);
        btcToken.mint(initialRecipient, initialRecipientAmount);
        console.log("Mock BTC deployed at:", address(btcToken));
        console.log("Minted balance:", btcToken.balanceOf(initialRecipient));
        return address(btcToken);
    }

     function setDeploymentConfig() public override {
        // Create asset for testnet
        OWNER = address(0x123); //your_deployer_address
        ASSET = createBTC(OWNER, 10_000e6);        
        SHARE_NAME = "xBTC.b";
        SHARE_SYMBOL = "xBTC.b";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 50000; // 0.0005 BTC
        MIN_DEPOSIT_AMOUNT = 7978; // 0.00007978 BTC => 10 USDC  // todo: need to be changed
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123); //your_fund_manager_wallet
        VARIABLE_VAULT_FEE = address(0x123); //your_deployed_xusdc_variable_vault_fee
    }
}