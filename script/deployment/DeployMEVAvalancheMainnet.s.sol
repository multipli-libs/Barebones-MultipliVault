// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {DeployMEVBase} from "./common/DeployMEV.s.sol";

/**
 * @title DeployMEVAvalancheMainnet
 * @notice Deploys MEV infrastructure to Avalanche C-Chain mainnet.
 * @dev Reads OWNER from environment variable MEV_DEPLOYER_ADDRESS.
 *      Aave V3 Pool on Avalanche mainnet: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
 *
 *      Usage:
 *        MEV_DEPLOYER_ADDRESS=0x... \
 *        forge script script/deployment/DeployMEVAvalancheMainnet.s.sol \
 *          --rpc-url avax_mainnet --broadcast --verify -vvvv
 *
 * @custom:security-contact security@multipli.com
 */
contract DeployMEVAvalancheMainnet is DeployMEVBase {
    function setMEVConfig() public override {
        OWNER = vm.envAddress("MEV_DEPLOYER_ADDRESS");

        // Aave V3 Pool — Avalanche C-Chain mainnet
        AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

        console.log("Config: Avalanche C-Chain mainnet deployment");
    }
}
