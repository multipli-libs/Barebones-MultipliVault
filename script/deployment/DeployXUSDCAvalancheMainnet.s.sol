// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {BaseDeployment} from "./Base.s.sol";

contract DeployXUSDCAvalancheMainnet is BaseDeployment {
     function setDeploymentConfig() public override {
       // For Avalanche C-Chain USDC
        OWNER = address(0x123); // your_deployer_address;
        ASSET = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // USDC (AVAX Mainnet)
        SHARE_NAME = "xUSDC";
        SHARE_SYMBOL = "xUSDC";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100e6; // 100 USDC
        MIN_DEPOSIT_AMOUNT = 10e6; // 10 USDC
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123); // your_fund_manager_wallet;

        console.log("Using mainnet configuration........");
    }
}