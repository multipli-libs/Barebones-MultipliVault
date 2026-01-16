pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {BaseDeployment} from "./Base.s.sol";

contract DeployXUSDCMonadMainnet is BaseDeployment {
     function setDeploymentConfig() public override {
       // For Monad USDC
        OWNER =  address(0x123);  // your_deployer_address
        ASSET = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
        SHARE_NAME = "xUSDC";
        SHARE_SYMBOL = "xUSDC";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100e6; // 100 USDC
        MIN_DEPOSIT_AMOUNT = 10e6; // 10 USDC
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123); // your_fund_manager_wallet;

        console.log("Using mainnet configuration........");
    }
}