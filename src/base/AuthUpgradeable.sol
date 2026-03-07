// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Authority } from "@solmate/auth/Auth.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title AuthUpgradeable
 * @notice Upgradable fork of https://github.com/transmissions11/solmate/blob/main/src/auth/Auth.sol
 * @dev Provides role-based authorization mechanism with upgradeability support.
 * @custom:security-contact security@multipli.com
 */
abstract contract AuthUpgradeable is Initializable {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @custom:storage-location erc7201:auth.storage
     * @dev Structure to hold authorization data.
     */
    struct AuthStorage {
        address owner;
        Authority authority;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Storage slot for the AuthStorage struct.
    // keccak256(abi.encode(uint256(keccak256("auth.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AuthStorageLocation =
        0xdd3fd67aef415aded9493b31ad20a02d2991d4bb2760431cc729821271eaea00;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when ownership is transferred.
     * @param user The address of the old owner.
     * @param newOwner The address receiving ownership.
     */
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    /**
     * @notice Emitted when the authority contract is updated.
     * @param user The address initiating the update.
     * @param newAuthority The new authority contract.
     */
    event AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AuthUpgradeable__Unauthorized();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modifier to restrict access to authorized users.
     */
    modifier requiresAuth() virtual {
        if (!isAuthorized(msg.sender, msg.sig)) {
            revert AuthUpgradeable__Unauthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the authority contract.
     * @param newAuthority The new authority contract.
     * @dev Can only be called by the owner or current authority.
     */
    function setAuthority(Authority newAuthority) public virtual {
        AuthStorage storage $ = _getAuthStorage();
        if (msg.sender != $.owner && !$.authority.canCall(msg.sender, address(this), msg.sig)) {
            revert AuthUpgradeable__Unauthorized();
        }
        $.authority = newAuthority;
        emit AuthorityUpdated(msg.sender, newAuthority);
    }

    /**
     * @notice Transfers ownership to a new address.
     * @param newOwner The address to receive ownership.
     * @dev Can only be called by an authorized user.
     */
    function transferOwnership(address newOwner) public virtual requiresAuth {
        AuthStorage storage $ = _getAuthStorage();
        $.owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a user is authorized to call a specific function.
     * @param user The address of the user.
     * @param functionSig The function signature being called.
     * @return bool True if authorized, false otherwise.
     */
    function isAuthorized(address user, bytes4 functionSig) public view virtual returns (bool) {
        AuthStorage storage $ = _getAuthStorage();
        Authority auth = $.authority;
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig))
            || user == $.owner;
    }

    /**
     * @notice Gets the address of the owner.
     * @return The address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _getAuthStorage().owner;
    }

    /**
     * @notice Gets the current authority contract.
     * @return The current authority contract address.
     */
    function authority() public view virtual returns (Authority) {
        return _getAuthStorage().authority;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with the specified owner and authority.
     * @param _owner The address of the initial owner.
     * @param _authority The initial authority contract.
     * @dev This function can only be called during contract initialization.
     */
    function __Auth_init(address _owner, Authority _authority) internal onlyInitializing {
        __Auth_init_unchained(_owner, _authority);
    }

    function __Auth_init_unchained(address _owner, Authority _authority) internal onlyInitializing {
        AuthStorage storage $ = _getAuthStorage();
        $.owner = _owner;
        $.authority = _authority;
        emit OwnershipTransferred(msg.sender, _owner);
        emit AuthorityUpdated(msg.sender, _authority);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns a reference to the AuthStorage struct.
     * @return $ Reference to the AuthStorage struct.
     */
    function _getAuthStorage() private pure returns (AuthStorage storage $) {
        assembly {
            $.slot := AuthStorageLocation
        }
    }
}
