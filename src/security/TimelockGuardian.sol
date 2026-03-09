// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Authority } from "@solmate/auth/Auth.sol";
import { IVariableVaultFee } from "../interfaces/IVariableVaultFee.sol";

/**
 * @title TimelockGuardian
 * @author Multipli Team
 * @notice Drainer-resistant governance contract for MultipliVault admin operations
 * @dev Enforces a timelock delay on critical operations (authority changes, upgrades,
 *      ownership transfers, fee contract changes). A separate guardian address can
 *      cancel pending operations and emergency-pause the vault without delay.
 *
 *      Deployment: Set this contract as the vault's `owner` via `transferOwnership`.
 *      The admin proposes operations, waits TIMELOCK_DELAY, then executes.
 *      If a key is compromised, the guardian cancels before execution.
 *
 * @custom:security-contact security@multipli.com
 */
contract TimelockGuardian {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Metadata for a pending timelocked operation
    struct PendingOp {
        uint256 executeAfter;
        bool exists;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum delay before a proposed operation can be executed
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    /// @notice Maximum time an operation remains executable after its delay
    uint256 public constant GRACE_PERIOD = 14 days;

    /// @notice The vault this guardian controls
    address public immutable vault;

    /// @notice Admin address — can propose and execute operations
    address public admin;

    /// @notice Guardian address — can cancel operations and emergency-pause (cold wallet /
    /// multisig)
    address public guardian;

    /// @notice Mapping of operation hash → pending operation metadata
    mapping(bytes32 => PendingOp) public pendingOps;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OperationProposed(bytes32 indexed opHash, address indexed target, uint256 executeAfter);
    event OperationExecuted(bytes32 indexed opHash);
    event OperationCancelled(bytes32 indexed opHash);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event GuardianTransferred(address indexed oldGuardian, address indexed newGuardian);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TimelockGuardian__OnlyAdmin();
    error TimelockGuardian__OnlyGuardian();
    error TimelockGuardian__OnlyAdminOrGuardian();
    error TimelockGuardian__ZeroAddress();
    error TimelockGuardian__OperationAlreadyPending();
    error TimelockGuardian__OperationNotPending();
    error TimelockGuardian__TimelockNotReady();
    error TimelockGuardian__OperationExpired();
    error TimelockGuardian__ExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdmin() {
        if (msg.sender != admin) revert TimelockGuardian__OnlyAdmin();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert TimelockGuardian__OnlyGuardian();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy the TimelockGuardian
     * @param _vault The vault address this guardian controls
     * @param _admin The admin address (hot wallet, can propose + execute)
     * @param _guardian The guardian address (cold wallet / multisig, can cancel + pause)
     */
    constructor(address _vault, address _admin, address _guardian) {
        if (_vault == address(0) || _admin == address(0) || _guardian == address(0)) {
            revert TimelockGuardian__ZeroAddress();
        }
        vault = _vault;
        admin = _admin;
        guardian = _guardian;
    }

    /*//////////////////////////////////////////////////////////////
              USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // ──────────────────────────────────────────────
    //  Propose → Execute pattern for critical ops
    // ──────────────────────────────────────────────

    /**
     * @notice Propose a timelocked call to the vault
     * @param data The ABI-encoded function call (e.g., setAuthority, transferOwnership)
     * @return opHash The unique hash identifying this operation
     */
    function propose(bytes calldata data) external onlyAdmin returns (bytes32 opHash) {
        opHash = keccak256(abi.encode(vault, data, block.timestamp));

        if (pendingOps[opHash].exists) {
            revert TimelockGuardian__OperationAlreadyPending();
        }

        uint256 executeAfter = block.timestamp + TIMELOCK_DELAY;
        pendingOps[opHash] = PendingOp({ executeAfter: executeAfter, exists: true });

        emit OperationProposed(opHash, vault, executeAfter);
    }

    /**
     * @notice Execute a previously proposed operation after timelock expires
     * @param data The same ABI-encoded function call that was proposed
     * @param proposedAt The block.timestamp when the operation was proposed
     */
    function execute(bytes calldata data, uint256 proposedAt) external onlyAdmin {
        bytes32 opHash = keccak256(abi.encode(vault, data, proposedAt));

        PendingOp storage op = pendingOps[opHash];
        if (!op.exists) revert TimelockGuardian__OperationNotPending();
        if (block.timestamp < op.executeAfter) revert TimelockGuardian__TimelockNotReady();
        if (block.timestamp > op.executeAfter + GRACE_PERIOD) {
            revert TimelockGuardian__OperationExpired();
        }

        delete pendingOps[opHash];

        (bool success,) = vault.call(data);
        if (!success) revert TimelockGuardian__ExecutionFailed();

        emit OperationExecuted(opHash);
    }

    /**
     * @notice Cancel a pending operation (guardian only — no timelock)
     * @param opHash The operation hash to cancel
     */
    function cancel(bytes32 opHash) external onlyGuardian {
        if (!pendingOps[opHash].exists) revert TimelockGuardian__OperationNotPending();
        delete pendingOps[opHash];
        emit OperationCancelled(opHash);
    }

    // ──────────────────────────────────────────────
    //  Emergency actions (no timelock)
    // ──────────────────────────────────────────────

    /**
     * @notice Emergency pause the vault — guardian only, no timelock
     * @dev Calls vault.pause() directly. Critical for responding to active exploits.
     */
    function emergencyPause() external onlyGuardian {
        (bool success,) = vault.call(abi.encodeWithSignature("pause()"));
        if (!success) revert TimelockGuardian__ExecutionFailed();
    }

    // ──────────────────────────────────────────────
    //  Guardian / Admin management
    // ──────────────────────────────────────────────

    /**
     * @notice Transfer admin role to a new address
     * @param newAdmin The new admin address
     * @dev This itself is NOT timelocked — but the admin can only propose ops,
     *      not execute them immediately. Guardian can always cancel.
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert TimelockGuardian__ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    /**
     * @notice Transfer guardian role to a new address
     * @param newGuardian The new guardian address
     * @dev Only current guardian can transfer. This is the "break glass" role.
     */
    function transferGuardian(address newGuardian) external onlyGuardian {
        if (newGuardian == address(0)) revert TimelockGuardian__ZeroAddress();
        emit GuardianTransferred(guardian, newGuardian);
        guardian = newGuardian;
    }
}
