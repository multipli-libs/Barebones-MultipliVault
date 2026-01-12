// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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
