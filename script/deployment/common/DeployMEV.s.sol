// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {MEVHub} from "src/mev/MEVHub.sol";
import {JaredExecutor} from "src/mev/JaredExecutor.sol";
import {SandwichStrategy} from "src/mev/strategies/SandwichStrategy.sol";
import {ArbitrageStrategy} from "src/mev/strategies/ArbitrageStrategy.sol";
import {JITStrategy} from "src/mev/strategies/JITStrategy.sol";

/**
 * @title DeployMEVBase
 * @notice Abstract base contract for MEV infrastructure deployment.
 * @dev Deploys:
 *      1. MEVHub — modular delegatecall hub with strategy registration
 *      2. JaredExecutor — monolithic single-byte dispatch executor
 *      3. Strategy modules — Sandwich, Arbitrage, JIT (registered on MEVHub)
 *
 *      Child contracts must implement `setMEVConfig()` to provide:
 *      - OWNER: deployer / admin address
 *      - AAVE_POOL: Aave V3 Pool address for the target network
 *
 * @custom:security-contact security@multipli.com
 */
abstract contract DeployMEVBase is Script {
    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public OWNER;
    address public AAVE_POOL;

    /*//////////////////////////////////////////////////////////////
                           DEPLOYED CONTRACTS
    //////////////////////////////////////////////////////////////*/

    MEVHub public mevHub;
    JaredExecutor public jaredExecutor;
    SandwichStrategy public sandwichStrategy;
    ArbitrageStrategy public arbitrageStrategy;
    JITStrategy public jitStrategy;

    /*//////////////////////////////////////////////////////////////
                           ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Must be implemented by child contracts to set OWNER and AAVE_POOL.
    function setMEVConfig() public virtual;

    /*//////////////////////////////////////////////////////////////
                           VALIDATION
    //////////////////////////////////////////////////////////////*/

    function validateMEVConfig() public view {
        if (OWNER == address(0)) revert("OWNER cannot be zero address");
        if (AAVE_POOL == address(0)) revert("AAVE_POOL cannot be zero address");

        console.log("===========================================");
        console.log("MEV Deployment Configuration");
        console.log("===========================================");
        console.log("OWNER:", OWNER);
        console.log("AAVE_POOL:", AAVE_POOL);
        console.log("===========================================");
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function deployMEV() public virtual {
        bool isFromTest = vm.envOr("IS_TEST", false);

        if (!isFromTest) {
            vm.startBroadcast();
        } else {
            vm.startPrank(OWNER);
        }

        setMEVConfig();
        validateMEVConfig();

        console.log("msg.sender: %s", msg.sender);
        console.log("block number: %d", block.number);

        // =============== DEPLOY STRATEGY MODULES ===============
        console.log("Deploying strategy modules...");

        sandwichStrategy = new SandwichStrategy();
        console.log("SandwichStrategy deployed at:", address(sandwichStrategy));

        arbitrageStrategy = new ArbitrageStrategy();
        console.log("ArbitrageStrategy deployed at:", address(arbitrageStrategy));

        jitStrategy = new JITStrategy();
        console.log("JITStrategy deployed at:", address(jitStrategy));
        // =============== ENDS HERE ================================

        // =============== DEPLOY MEV HUB ===============
        console.log("Deploying MEVHub...");
        mevHub = new MEVHub(OWNER, AAVE_POOL);
        console.log("MEVHub deployed at:", address(mevHub));
        // =============== ENDS HERE ================================

        // =============== REGISTER STRATEGIES ON HUB ===============
        console.log("Registering strategies on MEVHub...");

        mevHub.setStrategy(address(sandwichStrategy), true);
        console.log("  Registered SandwichStrategy");

        mevHub.setStrategy(address(arbitrageStrategy), true);
        console.log("  Registered ArbitrageStrategy");

        mevHub.setStrategy(address(jitStrategy), true);
        console.log("  Registered JITStrategy");
        // =============== ENDS HERE ================================

        // =============== DEPLOY JARED EXECUTOR ===============
        console.log("Deploying JaredExecutor...");
        jaredExecutor = new JaredExecutor(OWNER, AAVE_POOL);
        console.log("JaredExecutor deployed at:", address(jaredExecutor));
        // =============== ENDS HERE ================================

        if (isFromTest) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }

        // =============== POST-DEPLOYMENT SUMMARY ===============
        console.log("\n===========================================");
        console.log("MEV Deployment Summary");
        console.log("===========================================");
        console.log("MEVHub:             ", address(mevHub));
        console.log("JaredExecutor:      ", address(jaredExecutor));
        console.log("SandwichStrategy:   ", address(sandwichStrategy));
        console.log("ArbitrageStrategy:  ", address(arbitrageStrategy));
        console.log("JITStrategy:        ", address(jitStrategy));
        console.log("Owner:              ", OWNER);
        console.log("Aave Pool:          ", AAVE_POOL);
        console.log("===========================================");
    }

    function run() public virtual {
        console.log("Running MEV deployment: deployMEV()");
        deployMEV();
    }
}
