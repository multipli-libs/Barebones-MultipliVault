// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;


import {console} from "forge-std/console.sol";
import {BaseDeployment} from "./Base.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeployXUSDCAvalancheTestnet is BaseDeployment {
    function createUSDC(address initialRecipient, uint256 initialRecipientAmount) internal returns (address) {
        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 6);
        usdcToken.mint(initialRecipient, initialRecipientAmount);
        console.log("Mock USDC deployed at:", address(usdcToken));
        console.log("Minted balance:", usdcToken.balanceOf(initialRecipient));
        return address(usdcToken);
    }

     function setDeploymentConfig() public override {
        // Create asset for testnet
        OWNER = address(0x123); // your_deployer_address
        ASSET = createUSDC(OWNER, 10_000e6);        
        SHARE_NAME = "xUSDC";
        SHARE_SYMBOL = "xUSDC";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100e6; // 100 USDC
        MIN_DEPOSIT_AMOUNT = 10e6; // 10 USDC
        MULTIPLI_FUND_MANAGER_WALLET = address(0x123); // your_fund_manager_wallet;
    }
}