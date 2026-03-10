// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {console} from "forge-std/console.sol";
import {DeployMEVBase} from "./common/DeployMEV.s.sol";

/**
 * @title DeployMEVAnvil
 * @notice Deploys MEV infrastructure to local Anvil for testing.
 * @dev Uses Anvil's default deployer and a mock Aave pool address.
 *
 *      Usage:
 *        forge script script/deployment/DeployMEVAnvil.s.sol \
 *          --rpc-url anvil --broadcast -vvvv
 *
 * @custom:security-contact security@multipli.com
 */
contract DeployMEVAnvil is DeployMEVBase {
    function setMEVConfig() public override {
        // Anvil default account #0
        OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        // Mock Aave pool — use any non-zero address for local testing.
        // Flash loan callbacks won't work without a real pool, but all
        // other opcodes (swaps, arbs, JIT, batch) are fully testable.
        AAVE_POOL = address(0xAaAe1);

        console.log("Config: Anvil local deployment");
    }
}
