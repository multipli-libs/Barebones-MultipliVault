// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum Role {
    NONE, // 0 - default
    ADMIN, // 1
    FUND_MANAGER, // 2
    FUND_MANAGER_CONTRACT, // 3
    ORACLE, // 4
    EXTERNAL_CURATOR, // 5
    ETHEREUM_MIGRATOR_V1 //6
}
