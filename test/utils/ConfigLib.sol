// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ConfigLib {
    enum NetworkEnv { MAINNET, TESTNET, ANVIL }
    enum Network { ETHEREUM, BSC, AVALANCHE, TAC }
    enum TokenSymbol { USDC, WBTC, BTC_B}

    struct TokenConfig {
        address token;
        uint8 decimals;
        uint256 minDepositAmount;
        uint256 initialLockDepositAmount;
        string name;
        string vaultName;
        string vaultSymbol;
        string assetSymbol;
        bool isMock;   // This is used for the deployment script testcases on different environments
    }

    struct NetworkConfig {
        string rpcUrl;
        NetworkEnv env;
        TokenConfig tokenConfig;
    }

    function getConfig(
        Network network,
        NetworkEnv env,
        TokenSymbol token
    ) internal view returns (NetworkConfig memory) {
        if (network == Network.BSC) {
            return _bscConfig(env, token);
        } else if (network == Network.AVALANCHE) {
            return _avalancheConfig(env, token);
        } else if (network == Network.ETHEREUM) {
            return _ethereumConfig(env, token);
        } else if (network == Network.TAC){
            return _tacConfig(env,token);
        }

        revert("Unsupported network");
    }

    // BSC configs
    function _bscConfig(NetworkEnv env, TokenSymbol token) private view returns (NetworkConfig memory) {
        if (env == NetworkEnv.MAINNET) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "https://bsc-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, 
                        decimals: 18,
                        vaultName: "MultipliUSDCVault",
                        name: 'USDC',
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: false,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if (token == TokenSymbol.WBTC) {
                return NetworkConfig({
                    rpcUrl: "https://bsc-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c,
                        decimals: 8,
                        name: 'Bitcoin',
                        vaultName: "MultipliWBTCVault",
                        vaultSymbol: "xWBTC",
                        assetSymbol: 'WBTC',
                        isMock: false,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            }
        } else if (env == NetworkEnv.TESTNET || env == NetworkEnv.ANVIL) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl:  "https://bsc-testnet-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x18957C9A567baFD1B6f7d2A10158Aaaca90BEf4b,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVaultTest",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: true,
                        minDepositAmount:0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if (token == TokenSymbol.WBTC) {
                return NetworkConfig({
                    rpcUrl:  "https://bsc-testnet-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xFe6aF67DB42bBe0367E3F08D46523E8Ca0780476,
                        decimals: 18,
                        vaultName: "MultipliWBTCVaultTest",
                        name: 'Bitcoin',
                        vaultSymbol: "xWBTC",
                        assetSymbol: 'WBTC',
                        isMock: true,
                        minDepositAmount:0,
                        initialLockDepositAmount: 0
                    })
                });
            }
        }

        revert("Unsupported BSC config");
    }

    // Avalanche configs
    function _avalancheConfig(NetworkEnv env, TokenSymbol token) private view returns (NetworkConfig memory) {
        if (env == NetworkEnv.MAINNET) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "https://avalanche-c-chain-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVault",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: false,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if(token == TokenSymbol.BTC_B){
                return NetworkConfig({
                    rpcUrl: "https://avalanche-c-chain-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x152b9d0FdC40C096757F570A51E494bd4b943E50,
                        decimals: 8,
                        name: 'Bitcoin',
                        vaultName: "MultipliBTCVault",
                        vaultSymbol: "xBTC.b",
                        assetSymbol: 'BTC.b',
                        isMock: false,
                        minDepositAmount: 7978,
                        initialLockDepositAmount: 50000
                    })
                });
            }
        } else if (env == NetworkEnv.TESTNET || env == NetworkEnv.ANVIL) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "wss://avalanche-fuji-c-chain-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xE32175472F0b1b8712303EC16d238FD45E2aaBb1,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVaultTest",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: true,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if(token == TokenSymbol.BTC_B){
                return NetworkConfig({
                    rpcUrl: "wss://avalanche-fuji-c-chain-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xb1aa2AB2f90A0490b56F6676Eab9A0EBB3a74383,
                        decimals: 8,
                        name: 'Bitcoin',
                        vaultName: "MultipliUSDCVaultTest",
                        vaultSymbol: "xBTC.b",
                        assetSymbol: 'BTC.b',
                        isMock: true,
                        minDepositAmount: 7978,
                        initialLockDepositAmount: 50000
                    })
                });
            }
        }

        revert("Unsupported Avalanche config");
    }

    function _tacConfig(NetworkEnv env, TokenSymbol token) private view returns (NetworkConfig memory) {
        if (env == NetworkEnv.TESTNET || env == NetworkEnv.ANVIL) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "https://rpc.tac.build",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVaultTest",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: true,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            }
        }

        revert("Unsupported Tac config");
    }

    // Ethereum configs
    function _ethereumConfig(NetworkEnv env, TokenSymbol token) private view returns (NetworkConfig memory) {
        if (env == NetworkEnv.MAINNET) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "https://ethereum-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVault",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: false,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if (token == TokenSymbol.WBTC) {
                return NetworkConfig({
                    rpcUrl: "https://ethereum-rpc.publicnode.com",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                        decimals: 8,
                        name: 'Bitcoin',
                        vaultName: "MultipliWBTCVault",
                        vaultSymbol: "xWBTC",
                        assetSymbol: 'WBTC',
                        isMock: false,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            }
        } else if (env == NetworkEnv.TESTNET || env == NetworkEnv.ANVIL) {
            if (token == TokenSymbol.USDC) {
                return NetworkConfig({
                    rpcUrl: "https://sepolia.gateway.tenderly.co",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x6858aF063582c7d355bFbc711251ADF4Efbc4fd0,
                        decimals: 6,
                        name: 'USDC',
                        vaultName: "MultipliUSDCVaultTest",
                        vaultSymbol: "xUSDC",
                        assetSymbol: 'USDC',
                        isMock: true,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            } else if (token == TokenSymbol.WBTC) {
                return NetworkConfig({
                    rpcUrl: "https://sepolia.gateway.tenderly.co",
                    env: env,
                    tokenConfig: TokenConfig({
                        token: 0x29F53FFC222CD75805712c2dF76fA683c4b1e967,
                        decimals: 18,
                        name: 'Bitcoin',
                        vaultName: "MultipliWBTCVaultTest",
                        vaultSymbol: "xWBTC",
                        assetSymbol: 'WBTC',
                        isMock: true,
                        minDepositAmount: 0,
                        initialLockDepositAmount: 0
                    })
                });
            }
        }

        revert("Unsupported Ethereum config");
    }
}
