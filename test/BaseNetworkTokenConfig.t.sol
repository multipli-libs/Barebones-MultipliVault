// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ConfigLib} from "./utils/ConfigLib.sol";

import {Test} from "forge-std/Test.sol";

abstract contract BaseNetworkTokenConfig is Test {
    ConfigLib.NetworkConfig public config;

    struct TestConfig {
        ConfigLib.Network network;
        ConfigLib.NetworkEnv env;
        ConfigLib.TokenSymbol token;
    }

    TestConfig[] internal allConfigs;

    function _getEnvOrDefault(string memory key, string memory defaultValue) internal view returns (string memory) {
        try vm.envString(key) returns (string memory val) {
            return val;
        } catch {
            return defaultValue;
        }
    }

    function getQuantizedValue(uint256 unquantizedAmount) public view returns (uint256){
        return (unquantizedAmount* (10 ** config.tokenConfig.decimals));
    }

    function setTokenNetworkConfig() public virtual{
        string memory networkStr = _getEnvOrDefault("NETWORK", "avalanche");
        string memory envStr     = _getEnvOrDefault("ENV", "mainnet");
        string memory tokenStr   = _getEnvOrDefault("TOKEN", "usdc");  

        // Map env vars to enums
        ConfigLib.Network network = _parseNetwork(networkStr);
        ConfigLib.NetworkEnv env  = _parseEnv(envStr);
        ConfigLib.TokenSymbol symbol = _parseToken(tokenStr);

        config = ConfigLib.getConfig(network, env, symbol);
    }

    // ====================================== INTERNAL PARSERS ======================================

    function _parseNetwork(string memory s) internal pure returns (ConfigLib.Network) {
        if (_eq(s, "ethereum")) return ConfigLib.Network.ETHEREUM;
        if (_eq(s, "bsc")) return ConfigLib.Network.BSC;
        if (_eq(s, "avalanche")) return ConfigLib.Network.AVALANCHE;
        revert("Invalid NETWORK");
    }

    function _parseEnv(string memory s) internal pure returns (ConfigLib.NetworkEnv) {
        if (_eq(s, "mainnet")) return ConfigLib.NetworkEnv.MAINNET;
        if (_eq(s, "testnet")) return ConfigLib.NetworkEnv.TESTNET;
        revert("Invalid ENV");
    }

    function _parseToken(string memory s) internal pure returns (ConfigLib.TokenSymbol) {
        if (_eq(s, "usdc")) return ConfigLib.TokenSymbol.USDC;
        if (_eq(s, "wbtc")) return ConfigLib.TokenSymbol.WBTC;
        if (_eq(s, "btc.b")) return ConfigLib.TokenSymbol.BTC_B;
        revert("Invalid TOKEN");
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

}