// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { SovereignAccount } from "src/sovereign/SovereignAccount.sol";

/**
 * @title SovereignFactory
 * @notice CREATE2 factory for deterministic SovereignAccount deployment.
 * @dev Compatible with ERC-4337 initCode:
 *      abi.encodePacked(factory, abi.encodeCall(createAccount, (owner, salt)))
 *      WARNING: Get an audit before deploying to mainnet.
 * @custom:security-contact security@sovereign.account
 */
contract SovereignFactory {
    address public immutable ENTRY_POINT;

    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    constructor(address _entryPoint) {
        ENTRY_POINT = _entryPoint;
    }

    function createAccount(address owner, uint256 salt)
        external
        returns (SovereignAccount account)
    {
        bytes32 actualSalt = _salt(owner, salt);

        address predicted = getAddress(owner, salt);
        if (predicted.code.length > 0) {
            return SovereignAccount(payable(predicted));
        }

        account = new SovereignAccount{ salt: actualSalt }(owner, ENTRY_POINT);
        emit AccountCreated(address(account), owner, salt);
    }

    function getAddress(address owner, uint256 salt) public view returns (address predicted) {
        bytes32 actualSalt = _salt(owner, salt);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(SovereignAccount).creationCode, abi.encode(owner, ENTRY_POINT))
        );
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), actualSalt, initCodeHash)
                    )
                )
            )
        );
    }

    function _salt(address owner, uint256 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, salt));
    }
}
