// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMultipliVault {
    function adminMint(address receiver, uint256 shares) external;
    function aggregatedUnderlyingBalances() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function onUnderlyingBalanceUpdate(uint256 newAggregatedBalance) external;
}

/**
 * @title MultipliMigrator
 * @notice Enables secure and atomic migration of user balances from v1 to v2 vault
 * @custom:security-contact security@multipli.com
 */
contract MultipliMigrator is Ownable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // todo: what is a rational batch size
    uint256 public constant MAX_BATCH_SIZE = 10;

    IMultipliVault public vault;
    mapping(uint256 => bool) public migrationID;
    mapping(address => bool) public allowList;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateAllowList(address user, bool enable);
    event UserMigrated(uint256 newAggregatedBalance);
    event UserMigrated(
        uint256 indexed id, address indexed receiver, uint256 assets, uint256 shares
    );
    event UserMigrated(
        uint256 indexed id,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 newAggregatedBalance
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MultipliMigrator__InvalidAddress();
    error MultipliMigrator__InvalidBatchSize();
    error MultipliMigrator__ZeroAmount();
    error MultipliMigrator__UnAuthorized();
    error MultipliMigrator__IDAlreadyExists();
    error MultipliMigrator__AggregateBalanceMismatch();
    error MultipliMigrator__InsufficientSharesReceived(uint256 shares, uint256 minShares);
    error MultipliMigrator__ArrayLengthsMismatch();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier isAllowed() {
        if (!allowList[msg.sender]) {
            revert MultipliMigrator__UnAuthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _vault) Ownable(_owner) {
        if (_vault == address(0)) {
            revert MultipliMigrator__InvalidAddress();
        }

        vault = IMultipliVault(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateAllowList(address user, bool enable) external onlyOwner {
        if (user == address(0)) {
            revert MultipliMigrator__InvalidAddress();
        }

        if (allowList[user] != enable) {
            allowList[user] = enable;
            emit UpdateAllowList(user, enable);
        }
    }

    function adminMintSingle(
        uint256 id,
        address receiver,
        uint256 assets,
        uint256 minShares
    )
        public
        nonReentrant
        isAllowed
    {
        if (receiver == address(0)) revert MultipliMigrator__InvalidAddress();
        if (assets == 0) revert MultipliMigrator__ZeroAmount();
        if (migrationID[id]) revert MultipliMigrator__IDAlreadyExists();

        // mint shares to receiver
        uint256 shares = vault.previewDeposit(assets);
        if (shares < minShares) {
            revert MultipliMigrator__InsufficientSharesReceived(shares, minShares);
        }
        vault.adminMint(receiver, shares);

        // mark migration as completed
        migrationID[id] = true;

        // update underlying balance
        uint256 currentAggUnderlyingBalance = vault.aggregatedUnderlyingBalances();
        uint256 newAggregatedUnderlyingBalances = currentAggUnderlyingBalance + assets;
        vault.onUnderlyingBalanceUpdate(newAggregatedUnderlyingBalances);

        emit UserMigrated(id, receiver, assets, shares, newAggregatedUnderlyingBalances);
    }

    // todo: optimise this: two for-loops
    function adminMintBatch(
        uint256[] calldata ids,
        address[] calldata receivers,
        uint256[] calldata assets,
        uint256[] calldata minShares
    )
        public
        nonReentrant
        isAllowed
    {
        uint256 arrayLength = ids.length;
        if (arrayLength == 0 || arrayLength > MAX_BATCH_SIZE) {
            revert MultipliMigrator__InvalidBatchSize();
        }

        if (
            !(
                arrayLength == receivers.length && arrayLength == assets.length
                    && arrayLength == minShares.length
            )
        ) {
            revert MultipliMigrator__ArrayLengthsMismatch();
        }

        uint256 totalAssetsAdded;
        uint256 currentUnderlyingBalance = vault.aggregatedUnderlyingBalances();
        uint256[] memory sharesToMint = new uint256[](arrayLength);

        // First pass: Calculate all shares using current exchange rate
        for (uint256 i; i < arrayLength; ++i) {
            address _receiver = receivers[i];
            if (_receiver == address(0)) revert MultipliMigrator__InvalidAddress();

            uint256 _assets = assets[i];
            if (_assets == 0) revert MultipliMigrator__ZeroAmount();

            uint256 _id = ids[i];
            if (migrationID[_id]) revert MultipliMigrator__IDAlreadyExists();

            // mint shares to receiver
            uint256 _shares = vault.previewDeposit(_assets);
            uint256 _minShares = minShares[i];
            if (_shares < _minShares) {
                revert MultipliMigrator__InsufficientSharesReceived(_shares, _minShares);
            }
            sharesToMint[i] = _shares;
            migrationID[_id] = true;
            totalAssetsAdded += _assets;
        }

        // Second pass: Execute all mints
        for (uint256 i; i < arrayLength; ++i) {
            vault.adminMint(receivers[i], sharesToMint[i]);
            emit UserMigrated(ids[i], receivers[i], assets[i], sharesToMint[i]);
        }

        // update underlying balance
        uint256 updatedUnderlyingBalance = currentUnderlyingBalance + totalAssetsAdded;
        vault.onUnderlyingBalanceUpdate(updatedUnderlyingBalance);
        emit UserMigrated(updatedUnderlyingBalance);
    }
}
