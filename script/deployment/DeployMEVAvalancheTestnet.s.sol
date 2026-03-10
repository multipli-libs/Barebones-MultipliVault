// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {DeployMEVBase} from "./common/DeployMEV.s.sol";

/**
 * @title DeployMEVAvalancheTestnet
 * @notice Deploys MEV infrastructure to Avalanche Fuji testnet.
 * @dev Reads OWNER from environment variable MEV_DEPLOYER_ADDRESS.
 *      Aave V3 Pool on Fuji: 0xb3Ec5841b2f4a3e51A4b4236aE60e5C9e2eF5A8f
 *
 *      Usage:
 *        MEV_DEPLOYER_ADDRESS=0x... \
 *        forge script script/deployment/DeployMEVAvalancheTestnet.s.sol \
 *          --rpc-url avax_testnet --broadcast --verify -vvvv
 *
 * @custom:security-contact security@multipli.com
 */
contract DeployMEVAvalancheTestnet is DeployMEVBase {
    function setMEVConfig() public override {
        OWNER = vm.envAddress("MEV_DEPLOYER_ADDRESS");

        // Aave V3 Pool — Avalanche Fuji testnet
        AAVE_POOL = 0xB3eC5841B2f4a3e51A4b4236AE60e5C9e2ef5a8F;

        console.log("Config: Avalanche Fuji testnet deployment");
    }
}
