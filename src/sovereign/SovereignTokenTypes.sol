// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title SovereignTokenTypes
 * @notice 4-byte token type registry for ERC-6909 multi-token accounting.
 * @dev Each token type is a bytes4 selector derived from keccak256 of its canonical name,
 *      mirroring the function selector pattern. The bytes4 is cast to uint256 for ERC-6909 id.
 *
 *      Usage:  balanceOf(owner, uint256(VAULT_SHARE))
 *              transfer(receiver, uint256(REWARD_CLAIM), amount)
 *
 * @custom:security-contact security@multipli.com
 */
library SovereignTokenTypes {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Token type descriptor for off-chain indexing
    struct TokenMeta {
        bytes4 typeId;
        string name;
        string symbol;
        uint8 decimals;
    }

    /*//////////////////////////////////////////////////////////////
                         4-BYTE TOKEN TYPE IDS
    //////////////////////////////////////////////////////////////*/

    // ── Core Vault Tokens ────────────────────────────────────────

    /// @dev Vault share token — represents proportional ownership of vault assets
    bytes4 internal constant VAULT_SHARE = bytes4(keccak256("sovereign.token.VAULT_SHARE"));
    // 0x selector: cast to uint256 for ERC-6909 id

    /// @dev Vault debt token — represents borrowed position against vault collateral
    bytes4 internal constant VAULT_DEBT = bytes4(keccak256("sovereign.token.VAULT_DEBT"));

    // ── Yield & Rewards ──────────────────────────────────────────

    /// @dev Reward claim — accrued yield claimable by account holder
    bytes4 internal constant REWARD_CLAIM = bytes4(keccak256("sovereign.token.REWARD_CLAIM"));

    /// @dev Staking receipt — proof of staked position
    bytes4 internal constant STAKING_RECEIPT = bytes4(keccak256("sovereign.token.STAKING_RECEIPT"));

    /// @dev Vested allocation — time-locked token grant
    bytes4 internal constant VESTED_ALLOC = bytes4(keccak256("sovereign.token.VESTED_ALLOC"));

    // ── DeFi Primitives ──────────────────────────────────────────

    /// @dev LP position — liquidity provider share in a pool
    bytes4 internal constant LP_POSITION = bytes4(keccak256("sovereign.token.LP_POSITION"));

    /// @dev Collateral receipt — deposited collateral backing a loan
    bytes4 internal constant COLLATERAL = bytes4(keccak256("sovereign.token.COLLATERAL"));

    /// @dev Flash claim — ephemeral token for flash loan accounting
    bytes4 internal constant FLASH_CLAIM = bytes4(keccak256("sovereign.token.FLASH_CLAIM"));

    // ── Governance & Access ──────────────────────────────────────

    /// @dev Governance vote — voting power token
    bytes4 internal constant GOV_VOTE = bytes4(keccak256("sovereign.token.GOV_VOTE"));

    /// @dev Access badge — non-transferable permission token (soulbound pattern)
    bytes4 internal constant ACCESS_BADGE = bytes4(keccak256("sovereign.token.ACCESS_BADGE"));

    // ── Cross-Chain & Settlement ─────────────────────────────────

    /// @dev Bridge receipt — pending cross-chain transfer claim
    bytes4 internal constant BRIDGE_RECEIPT = bytes4(keccak256("sovereign.token.BRIDGE_RECEIPT"));

    /// @dev Settlement token — internal clearing unit for batch operations
    bytes4 internal constant SETTLEMENT = bytes4(keccak256("sovereign.token.SETTLEMENT"));

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error SovereignTokenTypes__UnknownType(bytes4 typeId);
    error SovereignTokenTypes__TypeAlreadyRegistered(bytes4 typeId);

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Derive a token type ID from a canonical name string
    /// @param name The canonical name (e.g., "sovereign.token.VAULT_SHARE")
    /// @return typeId The 4-byte type identifier
    function deriveTypeId(string calldata name) internal pure returns (bytes4 typeId) {
        typeId = bytes4(keccak256(bytes(name)));
    }

    /// @notice Convert a bytes4 token type to a flat ERC-6909 uint256 id
    /// @dev This reserves the upper 224 bits as zero. SovereignAccount `*Ref`
    ///      helpers intentionally use this flat namespace only.
    /// @param typeId The 4-byte token type
    /// @return id The uint256 id for ERC-6909 functions
    function toId(bytes4 typeId) internal pure returns (uint256 id) {
        id = uint256(uint32(typeId));
    }

    /// @notice Extract the bytes4 token type from a flat ERC-6909 uint256 id
    /// @dev Use unpackId for packed ids that encode a non-zero subId.
    /// @param id The uint256 id from ERC-6909
    /// @return typeId The 4-byte token type
    function fromId(uint256 id) internal pure returns (bytes4 typeId) {
        // forge-lint: disable-next-line(unsafe-typecast)
        typeId = bytes4(uint32(id));
    }

    /// @notice Pack a token type + sub-id into a single ERC-6909 uint256 id
    /// @dev Layout: [bytes4 typeId][uint224 subId]
    ///      Enables multiple instances of the same type (e.g., LP_POSITION for different pools)
    /// @param typeId The 4-byte token type
    /// @param subId The sub-identifier within that type
    /// @return id The packed uint256 id
    function packId(bytes4 typeId, uint224 subId) internal pure returns (uint256 id) {
        id = (uint256(uint32(typeId)) << 224) | uint256(subId);
    }

    /// @notice Unpack an ERC-6909 uint256 id into type + sub-id
    /// @param id The packed uint256 id
    /// @return typeId The 4-byte token type
    /// @return subId The sub-identifier
    function unpackId(uint256 id) internal pure returns (bytes4 typeId, uint224 subId) {
        // forge-lint: disable-next-line(unsafe-typecast)
        typeId = bytes4(uint32(id >> 224));
        // forge-lint: disable-next-line(unsafe-typecast)
        subId = uint224(id);
    }
}
