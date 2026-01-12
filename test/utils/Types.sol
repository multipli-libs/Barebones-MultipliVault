// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

enum NetworkEnv { MAINNET, TESTNET }

struct Users {
    address payable admin;
    uint256 adminKey;
    address payable bob;
    uint256 bobKey;
    address payable alice;
    uint256 aliceKey;
    address feeRecipient;
    uint256 feeRecipientKey;
}


struct NetworkConfig {
    string rpcUrl;
    address token;
    uint8 decimals;
    string vaultName;
    string vaultSymbol;
    NetworkEnv env;
}
