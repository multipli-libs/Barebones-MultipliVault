// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IAccount, PackedUserOperation } from "src/interfaces/erc4337/IAccount.sol";
import { SovereignTokenTypes } from "src/sovereign/SovereignTokenTypes.sol";
import { IERC6909, IERC6909TokenSupply } from "lib/openzeppelin-contracts/contracts/interfaces/IERC6909.sol";
import { IERC165 } from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

// ═══════════════════════════════════════════════════════════════
//
//  ███████╗ ██████╗ ██╗
// ██╗███████╗██████╗ ███████╗██╗
// ██████╗ ███╗   ██╗
//  ██╔════╝██╔═══██╗██║
// ██║██╔════╝██╔══██╗██╔════╝██║██╔════╝
// ████╗  ██║
//  ███████╗██║   ██║██║   ██║█████╗
// ██████╔╝█████╗  ██║██║  ███╗██╔██╗
// ██║
//  ╚════██║██║   ██║╚██╗ ██╔╝██╔══╝
// ██╔══██╗██╔══╝  ██║██║
// ██║██║╚██╗██║
//  ███████║╚██████╔╝ ╚████╔╝
// ███████╗██║
// ██║███████╗██║╚██████╔╝██║ ╚████║
//  ╚══════╝ ╚═════╝   ╚═══╝
// ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝
// ╚═════╝ ╚═╝  ╚═══╝
//
//  A Multi-EIP Creative ERC-4337 Smart Account
//
//  Fuses:  ERC-4337 + EIP-712 + ERC-1271 + EIP-1153 + ERC-7201
//
// 
// ┌──────────────────────────────────────────────────────────┐
//  │  1. Bitmap Permissions — granular capability bitmask     │
//  │  2. Session Keys — time & spend-scoped ephemeral signers │
//  │  3. Karma System — trust builds through tx success       │
//  │  4. Velocity Limiter — rolling-window rate limits        │
//  │  5. Dead Man's Switch — inactivity triggers recovery     │
//  │  6. Fallback Handlers — selector-based plugin system     │
//  │  7. EIP-1153 Transient Guard — ~100 gas reentrancy lock  │
//  │  8. ERC-1271 — on-chain signature validation             │
// 
// └──────────────────────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════

/**
 * @title SovereignAccount
 * @notice A creative ERC-4337 v0.7 smart account with adaptive, trust-aware security.
 * @dev Self-contained — no external dependencies beyond the ERC-4337 EntryPoint.
 *      WARNING: This is experimental — get an audit before deploying to mainnet.
 * @custom:security-contact security@sovereign.account
 */
contract SovereignAccount is IAccount, IERC6909TokenSupply {
    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    struct SessionKeyData {
        uint48 validAfter;
        uint48 validUntil;
        uint128 spendLimit;
        uint128 spent;
        uint256 permissions;
        bool active;
    }

    struct Karma {
        uint64 score;
        uint32 successes;
        uint32 failures;
    }

    struct VelocityConfig {
        uint128 maxPerWindow;
        uint48 windowDuration;
    }

    struct VelocityWindow {
        uint128 spent;
        uint48 windowStart;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public constant PERM_EXECUTE = 1 << 0;
    uint256 public constant PERM_MANAGE_ROLES = 1 << 1;
    uint256 public constant PERM_MANAGE_SESSION = 1 << 2;
    uint256 public constant PERM_MANAGE_GUARD = 1 << 3;
    uint256 public constant PERM_MANAGE_VELOCITY = 1 << 4;
    uint256 public constant PERM_MANAGE_HANDLER = 1 << 5;

    uint8 internal constant MODE_OWNER = 0x00;
    uint8 internal constant MODE_ROLE_SIGNER = 0x01;
    uint8 internal constant MODE_SESSION_KEY = 0x02;

    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    uint64 internal constant KARMA_SUCCESS_DELTA = 10;
    uint64 internal constant KARMA_FAILURE_DELTA = 25;
    uint64 internal constant KARMA_MAX = 1000;

    /// @dev EIP-1153 transient storage slots
    uint256 private constant _REENTRANCY_SLOT = 0x929eee149b4bd21268;
    uint256 private constant _SIGNER_SLOT = 0xa11cecede4c6c993bb;

    /// @dev secp256k1 half curve order — rejects malleable signatures
    uint256 private constant _HALF_CURVE_ORDER =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

    bytes32 private constant _DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    address public immutable ENTRY_POINT;
    address private immutable SELF;

    address public owner;

    mapping(address signer => uint256 permissionBitmap) public signerPermissions;
    mapping(address key => SessionKeyData data) public sessionKeys;
    mapping(address signer => Karma karmaData) public karma;
    mapping(address signer => VelocityWindow window) public velocityWindows;
    mapping(address guardian => bool isActive) public isGuardian;
    mapping(bytes4 selector => address handler) public fallbackHandlers;

    VelocityConfig public velocityConfig;

    /// @dev Packed into one slot: lastActivity (48) + inactivityThreshold (48) + guardianCount (8)
    /// + recoveryThreshold (8) + recoveryApprovals (8)
    uint48 public lastActivity;
    uint48 public inactivityThreshold;
    uint8 public guardianCount;
    uint8 public recoveryThreshold;
    uint8 public recoveryApprovals;

    bytes32 public activeRecoveryHash;
    uint48 public recoveryCreatedAt;
    uint256 public recoveryNonce;
    mapping(bytes32 recoveryHash => mapping(address guardian => bool voted)) public recoveryVotes;
    mapping(address account_ => mapping(uint256 id => uint256 amount)) internal erc6909Balances;
    mapping(address owner_ => mapping(address spender => mapping(uint256 id => uint256 amount)))
        internal erc6909Allowances;
    mapping(address owner_ => mapping(address spender => bool approved)) internal erc6909Operators;
    mapping(uint256 id => uint256 amount) internal erc6909TotalSupply;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Initialized(address indexed owner, address indexed entryPoint);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event RoleSet(address indexed signer, uint256 permissions);
    event RoleRevoked(address indexed signer);
    event SessionKeyCreated(address indexed key, uint48 validAfter, uint48 validUntil);
    event SessionKeyRevoked(address indexed key);
    event KarmaUpdated(address indexed signer, uint64 newScore, bool success);
    event VelocityConfigured(uint128 maxPerWindow, uint48 windowDuration);
    event DeadManConfigured(uint48 threshold);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event FallbackHandlerSet(bytes4 indexed selector, address indexed handler);
    event RecoveryInitiated(bytes32 indexed recoveryHash, address indexed newOwner);
    event RecoveryApproved(bytes32 indexed recoveryHash, address indexed guardian);
    event RecoveryExecuted(address indexed newOwner);
    event RecoveryCancelled();
    event RecoveryThresholdSet(uint8 threshold);
    event Executed(address indexed target, uint256 value, bool success);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SovereignAccount__Unauthorized();
    error SovereignAccount__InvalidSignature();
    error SovereignAccount__InsufficientKarma(uint256 limit, uint256 attempted);
    error SovereignAccount__VelocityExceeded(uint128 limit, uint128 attempted);
    error SovereignAccount__SessionSpendExceeded();
    error SovereignAccount__DeadManNotTriggered();
    error SovereignAccount__AlreadyApproved();
    error SovereignAccount__InvalidRecovery();
    error SovereignAccount__InvalidGuardianConfig();
    error SovereignAccount__Reentrancy();
    error SovereignAccount__ZeroAddress();
    error SovereignAccount__RecoveryAlreadyActive();
    error SovereignAccount__RecoveryExpired();
    error SovereignAccount__InvalidThreshold();
    error SovereignAccount__InsufficientBalance(uint256 available, uint256 required);
    error SovereignAccount__InsufficientAllowance(uint256 available, uint256 required);
    error SovereignAccount__EthForwardFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _entryPoint) {
        if (_owner == address(0) || _entryPoint == address(0)) {
            revert SovereignAccount__ZeroAddress();
        }
        SELF = address(this);
        owner = _owner;
        ENTRY_POINT = _entryPoint;

        lastActivity = uint48(block.timestamp);
        inactivityThreshold = 90 days;

        karma[_owner] = Karma({ score: KARMA_MAX, successes: 0, failures: 0 });

        emit Initialized(_owner, _entryPoint);
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        _forwardNativeToOwner();
    }

    fallback() external payable {
        address handler = fallbackHandlers[msg.sig];
        if (handler == address(0)) revert SovereignAccount__Unauthorized();

        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), handler, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        override
        returns (uint256 validationData)
    {
        if (msg.sender != ENTRY_POINT) revert SovereignAccount__Unauthorized();

        validationData = _validateSignature(userOp.signature, userOpHash);

        if (missingAccountFunds > 0) {
            assembly { pop(call(gas(), caller(), missingAccountFunds, 0, 0, 0, 0)) }
        }
    }

    /// @notice Execute a single call from this account.
    /// @dev On inner call failure, karma is decremented and an event is emitted
    ///      but the tx does NOT revert — this is intentional so the karma penalty
    ///      persists on-chain (a revert would roll it back).
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        payable
        returns (bool success, bytes memory result)
    {
        _requireEntryPointOrOwner();
        _setReentrancyGuard();
        _touchActivity();

        address cachedSigner = _tLoadSigner();

        _enforceKarma(cachedSigner, value);
        _enforceVelocity(cachedSigner, value);
        _enforceSessionSpend(cachedSigner, value);

        (success, result) = target.call{ value: value }(data);
        emit Executed(target, value, success);
        _updateKarma(cachedSigner, success);

        _clearReentrancyGuard();
    }

    /// @notice Execute a batch of calls. Stops at first failure.
    /// @dev Like execute(), does NOT revert so karma penalties persist.
    function executeBatch(Call[] calldata calls)
        external
        payable
        returns (bool success, bytes[] memory results)
    {
        _requireEntryPointOrOwner();
        _setReentrancyGuard();
        _touchActivity();

        address cachedSigner = _tLoadSigner();

        uint256 totalValue;
        for (uint256 i; i < calls.length; ++i) {
            totalValue += calls[i].value;
        }
        _enforceKarma(cachedSigner, totalValue);
        _enforceVelocity(cachedSigner, totalValue);
        _enforceSessionSpend(cachedSigner, totalValue);

        results = new bytes[](calls.length);
        success = true;

        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory result) =
                calls[i].target.call{ value: calls[i].value }(calls[i].data);
            emit Executed(calls[i].target, calls[i].value, ok);
            results[i] = result;

            if (!ok) {
                success = false;
                break;
            }
        }

        _updateKarma(cachedSigner, success);
        _clearReentrancyGuard();
    }

    function setRole(address signer, uint256 permissions) external {
        _requireOwnerOrPerm(PERM_MANAGE_ROLES);
        if (signer == address(0)) revert SovereignAccount__ZeroAddress();
        signerPermissions[signer] = permissions;
        emit RoleSet(signer, permissions);
    }

    function revokeRole(address signer) external {
        _requireOwnerOrPerm(PERM_MANAGE_ROLES);
        delete signerPermissions[signer];
        emit RoleRevoked(signer);
    }

    function createSessionKey(
        address key,
        uint256 permissions,
        uint48 validAfter,
        uint48 validUntil,
        uint128 spendLimit
    )
        external
    {
        _requireOwnerOrPerm(PERM_MANAGE_SESSION);
        if (key == address(0)) revert SovereignAccount__ZeroAddress();
        sessionKeys[key] = SessionKeyData({
            permissions: permissions,
            validAfter: validAfter,
            validUntil: validUntil,
            spendLimit: spendLimit,
            spent: 0,
            active: true
        });
        emit SessionKeyCreated(key, validAfter, validUntil);
    }

    function revokeSessionKey(address key) external {
        _requireOwnerOrPerm(PERM_MANAGE_SESSION);
        delete sessionKeys[key];
        emit SessionKeyRevoked(key);
    }

    function configureVelocity(uint128 maxPerWindow, uint48 windowDuration) external {
        _requireOwnerOrPerm(PERM_MANAGE_VELOCITY);
        velocityConfig =
            VelocityConfig({ maxPerWindow: maxPerWindow, windowDuration: windowDuration });
        emit VelocityConfigured(maxPerWindow, windowDuration);
    }

    function configureDeadMan(uint48 threshold) external {
        _requireOwner();
        if (threshold < 1 days) revert SovereignAccount__InvalidThreshold();
        inactivityThreshold = threshold;
        emit DeadManConfigured(threshold);
    }

    function addGuardian(address guardian) external {
        _requireOwnerOrPerm(PERM_MANAGE_GUARD);
        if (guardian == address(0)) revert SovereignAccount__ZeroAddress();
        if (!isGuardian[guardian]) {
            isGuardian[guardian] = true;
            guardianCount++;
            emit GuardianAdded(guardian);
        }
    }

    function removeGuardian(address guardian) external {
        _requireOwnerOrPerm(PERM_MANAGE_GUARD);
        if (isGuardian[guardian]) {
            uint8 newCount = guardianCount - 1;
            if (recoveryThreshold > 0 && newCount < recoveryThreshold) {
                revert SovereignAccount__InvalidGuardianConfig();
            }
            isGuardian[guardian] = false;
            guardianCount = newCount;
            emit GuardianRemoved(guardian);
        }
    }

    function setRecoveryThreshold(uint8 threshold) external {
        _requireOwnerOrPerm(PERM_MANAGE_GUARD);
        if (threshold == 0 || threshold > guardianCount) {
            revert SovereignAccount__InvalidGuardianConfig();
        }
        recoveryThreshold = threshold;
        emit RecoveryThresholdSet(threshold);
    }

    function initiateRecovery(address newOwner) external {
        if (!isGuardian[msg.sender]) revert SovereignAccount__Unauthorized();
        if (!_isDeadManTriggered()) revert SovereignAccount__DeadManNotTriggered();
        if (newOwner == address(0)) revert SovereignAccount__ZeroAddress();
        if (activeRecoveryHash != bytes32(0)) revert SovereignAccount__RecoveryAlreadyActive();

        recoveryNonce++;
        bytes32 rHash = keccak256(abi.encode(newOwner, recoveryNonce));

        activeRecoveryHash = rHash;
        recoveryCreatedAt = uint48(block.timestamp);
        recoveryApprovals = 1;
        recoveryVotes[rHash][msg.sender] = true;

        emit RecoveryInitiated(rHash, newOwner);
        emit RecoveryApproved(rHash, msg.sender);
    }

    function approveRecovery(address newOwner) external {
        if (!isGuardian[msg.sender]) revert SovereignAccount__Unauthorized();
        if (block.timestamp > uint256(recoveryCreatedAt) + 7 days) {
            revert SovereignAccount__RecoveryExpired();
        }

        bytes32 rHash = keccak256(abi.encode(newOwner, recoveryNonce));
        if (rHash != activeRecoveryHash) revert SovereignAccount__InvalidRecovery();
        if (recoveryVotes[rHash][msg.sender]) revert SovereignAccount__AlreadyApproved();

        recoveryVotes[rHash][msg.sender] = true;
        recoveryApprovals++;
        emit RecoveryApproved(rHash, msg.sender);

        if (recoveryApprovals >= recoveryThreshold) {
            _executeRecovery(newOwner);
        }
    }

    function cancelRecovery() external {
        _requireOwner();
        _touchActivity();
        delete activeRecoveryHash;
        delete recoveryCreatedAt;
        delete recoveryApprovals;
        emit RecoveryCancelled();
    }

    function setFallbackHandler(bytes4 selector, address handler) external {
        _requireOwnerOrPerm(PERM_MANAGE_HANDLER);
        fallbackHandlers[selector] = handler;
        emit FallbackHandlerSet(selector, handler);
    }

    function transferOwnership(address newOwner) external {
        _requireOwner();
        if (newOwner == address(0)) revert SovereignAccount__ZeroAddress();
        address old = owner;
        owner = newOwner;
        karma[newOwner] = Karma({ score: KARMA_MAX, successes: 0, failures: 0 });
        emit OwnerChanged(old, newOwner);
    }

    function approve(address spender, uint256 id, uint256 amount) external returns (bool) {
        _requireErc6909HolderAuthorized();
        _touchActivity();
        _approve6909(_erc6909Holder(), spender, id, amount);
        return true;
    }

    /// @notice Approve a flat 4-byte token type for spending.
    /// @dev Ref helpers intentionally operate on the base type id from
    ///      SovereignTokenTypes.toId(typeId). Use the raw ERC-6909 functions with
    ///      a packed id when working with non-zero subIds.
    function approveRef(address spender, bytes4 typeId, uint256 amount) external returns (bool) {
        _requireErc6909HolderAuthorized();
        _touchActivity();
        _approve6909(_erc6909Holder(), spender, SovereignTokenTypes.toId(typeId), amount);
        return true;
    }

    function setOperator(address spender, bool approved) external returns (bool) {
        _requireErc6909HolderAuthorized();
        _touchActivity();
        address actor = _erc6909Holder();
        erc6909Operators[actor][spender] = approved;
        emit OperatorSet(actor, spender, approved);
        return true;
    }

    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool) {
        _requireErc6909HolderAuthorized();
        _touchActivity();
        _transfer6909(_erc6909Holder(), receiver, id, amount);
        return true;
    }

    /// @notice Transfer a flat 4-byte token type.
    /// @dev Ref helpers target the base type id only; packed ids must be handled
    ///      through the raw ERC-6909 transfer functions.
    function transferRef(address receiver, bytes4 typeId, uint256 amount) external returns (bool) {
        _requireErc6909HolderAuthorized();
        _touchActivity();
        _transfer6909(_erc6909Holder(), receiver, SovereignTokenTypes.toId(typeId), amount);
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        external
        returns (bool)
    {
        _requireErc6909SpenderAuthorized();
        _touchActivity();
        address actor = _erc6909Actor();
        _spendAllowance6909(sender, actor, id, amount);
        _transfer6909(sender, receiver, id, amount);
        return true;
    }

    /// @notice Transfer a flat 4-byte token type on behalf of a holder.
    /// @dev Ref helpers target the base type id only; packed ids must be handled
    ///      through the raw ERC-6909 transfer functions.
    function transferFromRef(address sender, address receiver, bytes4 typeId, uint256 amount)
        external
        returns (bool)
    {
        _requireErc6909SpenderAuthorized();
        _touchActivity();
        uint256 id = SovereignTokenTypes.toId(typeId);
        address actor = _erc6909Actor();
        _spendAllowance6909(sender, actor, id, amount);
        _transfer6909(sender, receiver, id, amount);
        return true;
    }

    function mint(address receiver, uint256 id, uint256 amount) external {
        _requireDirectOwner();
        _mint6909(_erc6909Actor(), receiver, id, amount);
    }

    /// @notice Mint a flat 4-byte token type.
    /// @dev Ref helpers target the base type id only; packed ids must be minted
    ///      through the raw ERC-6909 mint path.
    function mintRef(address receiver, bytes4 typeId, uint256 amount) external {
        _requireDirectOwner();
        _mint6909(_erc6909Actor(), receiver, SovereignTokenTypes.toId(typeId), amount);
    }

    function burn(address holder, uint256 id, uint256 amount) external {
        _requireDirectOwner();
        _burn6909(_erc6909Actor(), holder, id, amount);
    }

    /// @notice Burn a flat 4-byte token type.
    /// @dev Ref helpers target the base type id only; packed ids must be burned
    ///      through the raw ERC-6909 burn path.
    function burnRef(address holder, bytes4 typeId, uint256 amount) external {
        _requireDirectOwner();
        _burn6909(_erc6909Actor(), holder, SovereignTokenTypes.toId(typeId), amount);
    }

    /*//////////////////////////////////////////////////////////////
                      USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC6909).interfaceId
            || interfaceId == type(IERC6909TokenSupply).interfaceId;
    }

    function balanceOf(address owner_, uint256 id) external view returns (uint256) {
        return erc6909Balances[owner_][id];
    }

    /// @notice Read balance for a flat 4-byte token type.
    /// @dev Packed ids with non-zero subIds are not aggregated into this view.
    function balanceOfRef(address owner_, bytes4 typeId) external view returns (uint256) {
        return erc6909Balances[owner_][SovereignTokenTypes.toId(typeId)];
    }

    function allowance(address owner_, address spender, uint256 id) external view returns (uint256) {
        return erc6909Allowances[owner_][spender][id];
    }

    function allowanceRef(address owner_, address spender, bytes4 typeId)
        external
        view
        returns (uint256)
    {
        return erc6909Allowances[owner_][spender][SovereignTokenTypes.toId(typeId)];
    }

    function isOperator(address owner_, address spender) external view returns (bool) {
        return erc6909Operators[owner_][spender];
    }

    function totalSupply(uint256 id) external view returns (uint256) {
        return erc6909TotalSupply[id];
    }

    /// @notice Read total supply for a flat 4-byte token type.
    /// @dev Packed ids with non-zero subIds are not aggregated into this view.
    function totalSupplyRef(bytes4 typeId) external view returns (uint256) {
        return erc6909TotalSupply[SovereignTokenTypes.toId(typeId)];
    }

    /// @notice Returns the spending tier for a karma score.
    ///  Karma tiers:
    ///    0-99    ->  0.1 ETH    |  100-299 ->  1 ETH
    ///    300-599 ->  10 ETH     |  600-999 ->  100 ETH
    ///    1000    ->  unlimited  |  Owner always unlimited
    function karmaSpendLimit(uint64 score) public pure returns (uint256 limit) {
        if (score >= 1000) return type(uint256).max;
        if (score >= 600) return 100 ether;
        if (score >= 300) return 10 ether;
        if (score >= 100) return 1 ether;
        return 0.1 ether;
    }

    function getKarma(address signer)
        external
        view
        returns (uint64 score, uint32 successes, uint32 failures)
    {
        Karma memory k = karma[signer];
        return (k.score, k.successes, k.failures);
    }

    function isDeadManTriggered() external view returns (bool) {
        return _isDeadManTriggered();
    }

    /// @notice Validates signatures on behalf of this account (e.g. for Permit2, Seaport).
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    )
        external
        view
        returns (bytes4 magicValue)
    {
        address recovered = _recover(_ethSignedHash(hash), signature);

        if (recovered == owner) return _ERC1271_MAGIC;
        if (signerPermissions[recovered] & PERM_EXECUTE != 0) return _ERC1271_MAGIC;

        return bytes4(0xffffffff);
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _DOMAIN_TYPEHASH,
                keccak256("SovereignAccount"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Signature layout:
    ///   [0]       mode byte
    ///   [1..]     mode-specific payload
    ///
    ///   MODE_OWNER       (0x00):  65-byte ECDSA sig
    ///   MODE_ROLE_SIGNER (0x01):  20-byte signer address + 65-byte ECDSA sig
    ///   MODE_SESSION_KEY (0x02):  20-byte session key   + 65-byte ECDSA sig
    function _validateSignature(bytes calldata sig, bytes32 userOpHash) internal returns (uint256) {
        if (sig.length < 1) return SIG_VALIDATION_FAILED;

        uint8 mode = uint8(sig[0]);

        if (mode == MODE_OWNER) return _validateOwner(userOpHash, sig[1:]);
        if (mode == MODE_ROLE_SIGNER) return _validateRoleSigner(userOpHash, sig[1:]);
        if (mode == MODE_SESSION_KEY) return _validateSessionKey(userOpHash, sig[1:]);

        return SIG_VALIDATION_FAILED;
    }

    function _validateOwner(bytes32 hash, bytes calldata sig) internal returns (uint256) {
        if (sig.length != 65) return SIG_VALIDATION_FAILED;

        address recovered = _recover(_ethSignedHash(hash), sig);
        if (recovered != owner) return SIG_VALIDATION_FAILED;

        _tStoreSigner(recovered);
        return SIG_VALIDATION_SUCCESS;
    }

    function _validateRoleSigner(bytes32 hash, bytes calldata sig) internal returns (uint256) {
        if (sig.length != 85) return SIG_VALIDATION_FAILED;

        address signer = address(bytes20(sig[:20]));
        bytes calldata raw = sig[20:85];

        address recovered = _recover(_ethSignedHash(hash), raw);
        if (recovered != signer) return SIG_VALIDATION_FAILED;
        if (signerPermissions[signer] & PERM_EXECUTE == 0) return SIG_VALIDATION_FAILED;

        _tStoreSigner(signer);
        return SIG_VALIDATION_SUCCESS;
    }

    function _validateSessionKey(bytes32 hash, bytes calldata sig) internal returns (uint256) {
        if (sig.length != 85) return SIG_VALIDATION_FAILED;

        address key = address(bytes20(sig[:20]));
        bytes calldata raw = sig[20:85];

        SessionKeyData storage skd = sessionKeys[key];
        if (!skd.active) return SIG_VALIDATION_FAILED;

        address recovered = _recover(_ethSignedHash(hash), raw);
        if (recovered != key) return SIG_VALIDATION_FAILED;

        _tStoreSigner(key);
        return _packValidationData(0, skd.validAfter, skd.validUntil);
    }

    function _enforceKarma(address signer, uint256 value) internal view {
        if (signer == owner) return;

        uint256 limit = karmaSpendLimit(karma[signer].score);
        if (value > limit) revert SovereignAccount__InsufficientKarma(limit, value);
    }

    function _updateKarma(address signer, bool success) internal {
        if (signer == owner) return;

        Karma storage k = karma[signer];
        if (success) {
            k.successes++;
            uint64 newScore = k.score + KARMA_SUCCESS_DELTA;
            k.score = newScore > KARMA_MAX ? KARMA_MAX : newScore;
        } else {
            k.failures++;
            k.score = k.score >= KARMA_FAILURE_DELTA ? k.score - KARMA_FAILURE_DELTA : 0;
        }
        emit KarmaUpdated(signer, k.score, success);
    }

    function _enforceVelocity(address signer, uint256 value) internal {
        if (signer == owner) return;

        VelocityConfig memory vc = velocityConfig;
        if (vc.maxPerWindow == 0) return;

        VelocityWindow storage vw = velocityWindows[signer];

        if (block.timestamp >= uint256(vw.windowStart) + uint256(vc.windowDuration)) {
            vw.spent = 0;
            vw.windowStart = uint48(block.timestamp);
        }

        if (value > type(uint128).max) {
            revert SovereignAccount__VelocityExceeded(vc.maxPerWindow, type(uint128).max);
        }
        uint128 newSpent = vw.spent + uint128(value);
        if (newSpent > vc.maxPerWindow) {
            revert SovereignAccount__VelocityExceeded(vc.maxPerWindow, newSpent);
        }
        vw.spent = newSpent;
    }

    function _enforceSessionSpend(address signer, uint256 value) internal {
        SessionKeyData storage skd = sessionKeys[signer];
        if (!skd.active) return;

        if (value > type(uint128).max) revert SovereignAccount__SessionSpendExceeded();
        uint128 newSpent = skd.spent + uint128(value);
        if (newSpent > skd.spendLimit) revert SovereignAccount__SessionSpendExceeded();
        skd.spent = newSpent;
    }

    function _executeRecovery(address newOwner) internal {
        address oldOwner = owner;
        owner = newOwner;
        lastActivity = uint48(block.timestamp);
        karma[newOwner] = Karma({ score: KARMA_MAX, successes: 0, failures: 0 });

        delete activeRecoveryHash;
        delete recoveryCreatedAt;
        delete recoveryApprovals;

        emit RecoveryExecuted(newOwner);
        emit OwnerChanged(oldOwner, newOwner);
    }

    function _approve6909(address owner_, address spender, uint256 id, uint256 amount) internal {
        erc6909Allowances[owner_][spender][id] = amount;
        emit Approval(owner_, spender, id, amount);
    }

    function _transfer6909(address sender, address receiver, uint256 id, uint256 amount) internal {
        if (sender == address(0) || receiver == address(0)) revert SovereignAccount__ZeroAddress();

        uint256 senderBalance = erc6909Balances[sender][id];
        if (senderBalance < amount) {
            revert SovereignAccount__InsufficientBalance(senderBalance, amount);
        }

        erc6909Balances[sender][id] = senderBalance - amount;
        erc6909Balances[receiver][id] += amount;

        emit Transfer(_erc6909Actor(), sender, receiver, id, amount);
    }

    function _mint6909(address caller_, address receiver, uint256 id, uint256 amount) internal {
        if (receiver == address(0)) revert SovereignAccount__ZeroAddress();

        erc6909Balances[receiver][id] += amount;
        erc6909TotalSupply[id] += amount;

        emit Transfer(caller_, address(0), receiver, id, amount);
    }

    function _burn6909(address caller_, address holder, uint256 id, uint256 amount) internal {
        if (holder == address(0)) revert SovereignAccount__ZeroAddress();

        uint256 holderBalance = erc6909Balances[holder][id];
        if (holderBalance < amount) {
            revert SovereignAccount__InsufficientBalance(holderBalance, amount);
        }

        erc6909Balances[holder][id] = holderBalance - amount;
        erc6909TotalSupply[id] -= amount;

        emit Transfer(caller_, holder, address(0), id, amount);
    }

    /// @dev EIP-1153: store validated signer in transient storage so execution
    ///      phase knows who authenticated without a permanent SSTORE (~100 gas vs ~20,000).
    function _tStoreSigner(address signer) internal {
        assembly { tstore(_SIGNER_SLOT, signer) }
    }

    function _setReentrancyGuard() internal {
        bool locked;
        assembly { locked := tload(_REENTRANCY_SLOT) }
        if (locked) revert SovereignAccount__Reentrancy();
        assembly { tstore(_REENTRANCY_SLOT, 1) }
    }

    function _clearReentrancyGuard() internal {
        assembly { tstore(_REENTRANCY_SLOT, 0) }
    }

    function _touchActivity() internal {
        lastActivity = uint48(block.timestamp);
    }

    function _forwardNativeToOwner() internal {
        if (msg.value == 0) return;

        (bool success,) = owner.call{value: msg.value}("");
        if (!success) revert SovereignAccount__EthForwardFailed();
    }

    function _requireOwner() internal view {
        if (msg.sender != owner && msg.sender != address(this)) {
            revert SovereignAccount__Unauthorized();
        }
    }

    function _requireDirectOwner() internal view {
        if (msg.sender != owner) revert SovereignAccount__Unauthorized();
    }

    function _requireEntryPointOrOwner() internal view {
        if (msg.sender != ENTRY_POINT && msg.sender != owner && msg.sender != address(this)) {
            revert SovereignAccount__Unauthorized();
        }
    }

    function _requireOwnerOrPerm(uint256 perm) internal view {
        if (msg.sender == owner || msg.sender == address(this)) return;
        if (msg.sender == ENTRY_POINT) return;
        if (signerPermissions[msg.sender] & perm != 0) return;
        revert SovereignAccount__Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _recover(bytes32 hash, bytes calldata sig) internal pure returns (address recovered) {
        if (sig.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 0x20))
            v := byte(0, calldataload(add(sig.offset, 0x40)))
        }

        if (uint256(s) > _HALF_CURVE_ORDER) return address(0);
        if (v != 27 && v != 28) return address(0);

        recovered = ecrecover(hash, v, r, s);
    }

    function _ethSignedHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _tLoadSignerRaw() internal view returns (address signer) {
        assembly { signer := tload(_SIGNER_SLOT) }
    }

    function _tLoadSigner() internal view returns (address signer) {
        signer = _tLoadSignerRaw();
        if (signer == address(0)) signer = msg.sender;
    }

    function _isDeadManTriggered() internal view returns (bool) {
        return block.timestamp > uint256(lastActivity) + uint256(inactivityThreshold);
    }

    function _packValidationData(
        uint256 authorizer,
        uint48 validAfter,
        uint48 validUntil
    )
        internal
        pure
        returns (uint256)
    {
        return (uint256(validAfter) << 208) | (uint256(validUntil) << 160) | authorizer;
    }

    function _spendAllowance6909(address sender, address spender, uint256 id, uint256 amount)
        internal
    {
        if (spender == sender || erc6909Operators[sender][spender]) return;

        uint256 currentAllowance = erc6909Allowances[sender][spender][id];
        if (currentAllowance < amount) {
            revert SovereignAccount__InsufficientAllowance(currentAllowance, amount);
        }

        if (currentAllowance != type(uint256).max) {
            erc6909Allowances[sender][spender][id] = currentAllowance - amount;
        }
    }

    function _erc6909Actor() internal view returns (address actor) {
        actor = msg.sender;
        if (actor == ENTRY_POINT || actor == address(this)) {
            actor = address(this);
        }
    }

    function _erc6909Holder() internal view returns (address holder) {
        holder = msg.sender;
        if (_isDelegateContext() || holder == ENTRY_POINT || holder == address(this)) {
            holder = address(this);
        }
    }

    function _isDelegateContext() internal view returns (bool) {
        return address(this) != SELF;
    }

    function _requireErc6909Controller(address authorizedCaller) internal view {
        if (authorizedCaller == owner) return;
        if (signerPermissions[authorizedCaller] & PERM_EXECUTE != 0) return;

        SessionKeyData storage skd = sessionKeys[authorizedCaller];
        if (!skd.active) revert SovereignAccount__Unauthorized();
        if (skd.permissions & PERM_EXECUTE == 0) revert SovereignAccount__Unauthorized();
        if (block.timestamp < uint256(skd.validAfter)) revert SovereignAccount__Unauthorized();
        if (skd.validUntil != 0 && block.timestamp > uint256(skd.validUntil)) {
            revert SovereignAccount__Unauthorized();
        }
    }

    function _requireErc6909WrappedAuthorized() internal view {
        address authorizedCaller = msg.sender;

        if (authorizedCaller != ENTRY_POINT && authorizedCaller != address(this)) {
            return;
        }

        if (authorizedCaller == address(this)) {
            authorizedCaller = _tLoadSignerRaw();
            if (authorizedCaller == address(0)) {
                if (tx.origin == address(this)) return;
                revert SovereignAccount__Unauthorized();
            }
        } else {
            authorizedCaller = _tLoadSigner();
        }

        _requireErc6909Controller(authorizedCaller);
    }

    function _requireErc6909HolderAuthorized() internal view {
        if (_isDelegateContext()) {
            _requireErc6909Controller(msg.sender);
            return;
        }

        _requireErc6909WrappedAuthorized();
    }

    function _requireErc6909SpenderAuthorized() internal view {
        if (_isDelegateContext()) return;
        _requireErc6909WrappedAuthorized();
    }
}
