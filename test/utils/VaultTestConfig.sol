// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library VaultTestConfig {
    enum Network {
        AvaxMainnet,
        AvaxTestnet,
        AvaxAnvil,
        TacAnvil,
        TacTestnet
    }

    /// @dev Environment configuration for vault testing
    struct VaultEnvConfig {
        bool isMock; // true = mock ERC20 + local test setup; false = forked mainnet
        string rpc; // Mainnet RPC endpoint used for creating fork during test setup
        address underlyingToken; // USDC token address on the mainnet; used for verification in deployment
    }

    function getConfig(Network network) internal pure returns (VaultEnvConfig memory config) {
        if (network == Network.AvaxMainnet) {
            return VaultEnvConfig({
                isMock: false,
                rpc: "https://api.avax.network/ext/bc/C/rpc",
                underlyingToken: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E
            });
        } else if (network == Network.AvaxTestnet || network == Network.AvaxAnvil) {
            return VaultEnvConfig({
                isMock: true,
                rpc: "https://api.avax.network/ext/bc/C/rpc",
                underlyingToken: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E
            });
        } else if (network == Network.TacAnvil || network == Network.TacTestnet) {
            return VaultEnvConfig({
                isMock: true,
                rpc: "https://rpc.tac.build",
                underlyingToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
            });
        } else {
            revert("Unknown network");
        }
    }
}
