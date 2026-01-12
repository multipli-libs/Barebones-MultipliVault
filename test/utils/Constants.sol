// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import { Role } from "../../src/common/Role.sol";

abstract contract Constants {
    uint8 internal constant ADMIN_ROLE = uint8(Role.ADMIN);
    uint8 internal constant FUND_MANAGER_ROLE = uint8(Role.FUND_MANAGER);
    uint8 internal constant FUND_MANAGER_CONTRACT_ROLE = uint8(Role.FUND_MANAGER_CONTRACT);
    uint8 internal constant ORACLE_ROLE = uint8(Role.ORACLE);
    uint8 internal constant EXTERNAL_CURATOR_ROLE = uint8(Role.EXTERNAL_CURATOR);

    uint256 internal constant MAX_FEE = 1e17;

    uint256 internal constant MAX_PERCENTAGE_THRESHOLD = 1e17;

    uint256 internal constant DENOMINATOR = 1e18;
    address public DEPLOYER_ADDRESS = 0x8cFee31bf3A57EC2C86D9e0f476Bd36aCA611Fa5;
    address public VARIABLE_VAULT_FEE_CONTRACT_ADDRESS = 0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72;
    
}
