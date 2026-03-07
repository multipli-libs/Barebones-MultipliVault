// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {BaseDeployment} from "./common/Base.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeployXUSDCAvalancheAnvil is BaseDeployment {
    function createUSDC(address initialRecipient, uint256 initialRecipientAmount) internal returns (address) {
        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 6);
        usdcToken.mint(initialRecipient, initialRecipientAmount);
        console.log("Mock USDC deployed at:", address(usdcToken));
        console.log("Minted balance:", usdcToken.balanceOf(initialRecipient));
        return address(usdcToken);
    }

     function setDeploymentConfig() public override {
        // Create asset for testnet
        OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        ASSET = createUSDC(OWNER, 10_000e6);  
        SHARE_NAME = "xUSDC";
        SHARE_SYMBOL = "xUSDC";
        INITIAL_LOCK_DEPOSIT_AMOUNT = 100e6; // 100 USDC
        MIN_DEPOSIT_AMOUNT = 10e6; // 10 USDC
        MULTIPLI_FUND_MANAGER_WALLET = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }
}