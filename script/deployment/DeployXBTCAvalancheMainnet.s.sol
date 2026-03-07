// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {BaseWithSharedConfig} from "./common/BaseWithSharedConfig.s.sol";
import {console} from "forge-std/Script.sol";

contract DeployXBTCAvalancheMainnet is BaseWithSharedConfig {
     function setDeploymentConfig() public override {
       // For Avalanche C-Chain BTC.b
        OWNER = address(0x123); //your_deployer_address
        ASSET = 0x152b9d0FdC40C096757F570A51E494bd4b943E50; // BTC.b (AVAX Mainnet)
        SHARE_NAME = "xBTC.b";
        SHARE_SYMBOL = "xBTC.b";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 50000; // 0.0005 BTC
        MIN_DEPOSIT_AMOUNT = 7978; // 0.00007978 BTC => 10 USDC  // todo: need to be changed
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123); //your_fund_manager_wallet
        VARIABLE_VAULT_FEE = address(0x123); //your_deployed_xusdc_variable_vault_fee

        console.log("Using mainnet configuration........");
    }
}