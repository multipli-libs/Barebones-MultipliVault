# Multipli Protocol - Documentation

Multipli is a Real World Asset (RWA) yield protocol that employs delta neutral strategies to generate consistent yield. Delta neutral strategies maintain a balanced position where the portfolio's value remains relatively stable regardless of market price movements, allowing the protocol to capture yield from various sources while minimizing directional risk.

This repository contains the smart contract implementation for the Multipli Protocol, providing ERC-4626 compatible vault interfaces that integrate seamlessly with the broader DeFi ecosystem. The protocol is deployed using the [UUPS proxy pattern](https://docs.openzeppelin.com/contracts/4.x/api/proxy), which enables secure upgradability while maintaining a single contract address.

> **Note:** This repository is a **stripped-down, deployment-focused subset** of the full Multipli Protocol codebase. Active development, experimentation, and internal tooling occur in a separate internal repository; only the contracts and components required for deployment, verification, and external review are included here.
>
> This repository contains the **V1 version** of the Multipli Protocol contracts. To review the **V2 version**, please refer to the [`v2` branch](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2).

## 1. Repository Structure

This repository contains the core smart contracts and deployment scripts for the Multipli Protocol.

### 1.1 Versions

- **V1 (v1 branch)**: Initial implementation featuring xUSDC vault on Avalanche C-Chain and Monad
- **V2 (main branch)**: Enhanced version with multi-chain support and additional features - [View V2 Documentation](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2)

## 2. Local Setup

1. **Clone the repository**

```bash
   git clone <repository-url>
   cd <repository-name>
```

2. **Install Forge dependencies**

```bash
   forge install
```

3. **Install Node.js dependencies**

```bash
   # Ensure you're using Node.js version 20 or higher
   node -v # Should show v20.x.x or higher
   npm install
```

4. **Create deployment wallets**

```bash
   # Create wallets for different environments
   # Create wallets for different environments
    cast wallet import <your_avalanche_mainnet_wallet> --interactive   # Avalanche mainnet deployment
    cast wallet import <your_monad_mainnet_wallet> --interactive       # Monad mainnet deployment
    cast wallet import <your_avalanche_testnet_wallet> --interactive   # Avalanche testnet deployment
    cast wallet import <your_monad_testnet_wallet> --interactive       # Monad testnet deployment
    cast wallet import <your_local_deployer_wallet> --interactive     # Local testing

```

5. **Configure environment variables**

```bash
   # Create .env file with RPC URLs and API keys
   cp .env.example .env
   # Edit .env with your configuration
```

### 2.1 Build and Test

```bash
# Build contracts
forge build

# Run tests with detailed output
forge clean && forge build && forge test -vvvv

# Generate gas snapshots
forge snapshot
```

### 2.2 Help

```bash
forge --help
anvil --help
cast --help
```

## 3. Deployment

The repository includes deployment scripts for different networks in the `script/deployment/` directory:

- **Mainnet deployments**: `script/deployment/Deploy[vault][network]Mainnet.s.sol`
- **Testnet deployments**: `script/deployment/Deploy[vault][network]Testnet.s.sol`
- **Local deployments**: `script/deployment/Deploy[vault][network]Anvil.s.sol`

### 3.1 Pre-Deployment Checklist

1. **Configure deployment parameters** in the relevant deployment script:

   - Update `OWNER` to your deployer address
   - Update `MULTIPLI_FUND_MANAGER_WALLET` to your fund manager address
   - Verify `ASSET`, `SHARE_NAME`, `SHARE_SYMBOL` are correct
   - Confirm `INITIAL_LOCK_DEPOSIT_AMOUNT` and `MIN_DEPOSIT_AMOUNT`

2. **Ensure wallet has sufficient funds**:

   - Native tokens for gas fees
   - Underlying asset tokens for initial deposit

3. **Set up RPC endpoints** in foundry.toml or .env file

### 3.2 Deployment Commands

#### 3.2.1 Avalanche Mainnet

```bash
forge script script/deployment/DeployXUSDCAvalancheMainnet.s.sol:DeployXUSDCAvalancheMainnet \
  --rpc-url avax_mainnet \
  --account <your_avalanche_mainnet_wallet> \
  --sender <your_deployer_address> \
  --verify \
  --broadcast \
  -vvvv
```

#### 3.2.2 Monad Mainnet

```bash
forge script script/deployment/DeployXUSDCMonadMainnet.s.sol:DeployXUSDCMonadMainnet \
  --rpc-url monad_mainnet \
  --account <your_monad_mainnet_wallet> \
  --sender <your_deployer_address> \
  --verify \
  --broadcast \
  -vvvv
```

#### 3.2.3 Avalanche Testnet Deployment

```bash
forge script script/deployment/DeployXUSDCAvalancheTestnet.s.sol:DeployXUSDCAvalancheTestnet \
  --rpc-url avax_testnet \
  --account <your_avalanche_testnet_wallet> \
  --sender <your_deployer_address> \
  --verify \
  --broadcast \
  -vvvv
```

#### 3.2.4 Monad Testnet Deployment

```bash
forge script script/deployment/DeployXUSDCAvalancheTestnet.s.sol:DeployXUSDCAvalancheTestnet \
  --rpc-url avax_testnet \
  --account <your_monad_testnet_wallet> \
  --sender <your_deployer_address> \
  --verify \
  --broadcast \
  -vvvv
```

#### 3.2.5 Local Deployment (Anvil)

```bash
# Start Anvil in a separate terminal first
anvil

# Then deploy
forge script script/deployment/anvil/DeployXUSDCAnvil.s.sol:DeployXUSDCAnvil \
  --rpc-url localhost \
  --account <your_local_deployer_wallet> \
  --sender <your_deployer_address> \
  --broadcast \
  -vvvv
```

### 3.3 Post-Deployment Verification

After deployment, verify that:

1. All contracts are deployed and verified on the block explorer
2. Initial deposit was successful
3. Roles and permissions are correctly configured
4. Fee structures are properly set

### 3.4 Manual Contract Verification

If the `--verify` flag doesn't verify all contracts (particularly implementation contracts), use manual verification:

```bash
forge verify-contract \
  --chain-id <chain_id> \
  <implementation_address> \
  src/vault/MultipliVault.sol:MultipliVault \
  --compiler-version v0.8.30+commit.2fe13dce \
  --verifier-url '<explorer_api_url>' \
  --etherscan-api-key <your_api_key> \
  --watch
```

**Example for Avalanche Mainnet (Snowtrace via RouteScan):**

```bash
forge verify-contract \
  --chain-id 43114 \
  0x2a66bb2da3ad1c854e79307f64b862decd860d4c \
  src/vault/MultipliVault.sol:MultipliVault \
  --compiler-version v0.8.30+commit.2fe13dce \
  --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' \
  --etherscan-api-key <your_api_key> \
  --watch
```

## 4. Deployed Contracts

### 4.1 Deployed Contracts (V1)

📌 **Source Code:**  
[V1 branch](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v1)

---

#### Avalanche C-Chain (Mainnet)

The following contracts are deployed on Avalanche C-Chain:

| Contract                  | Address                                                                                                                 | Description                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **MultipliVault (xUSDC)** | [`0xCF0Eb4ac018C06a16ED5c63484823C7805e7599D`](https://snowtrace.io/address/0xCF0Eb4ac018C06a16ED5c63484823C7805e7599D) | Core vault contract for USDC deposits       |
| **VaultFundManager**      | [`0x01e676EAA0C9780A88395c651349Cf08Fe52368e`](https://snowtrace.io/address/0x01e676EAA0C9780A88395c651349Cf08Fe52368e) | Manages fund movements and balance updates  |
| **VariableVaultFee**      | [`0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72`](https://snowtrace.io/address/0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72) | Handles fee calculations and configurations |
| **RolesAuthority**        | [`0xf580B985e2Fd8A8b0e4a56C2a7E24bC28e872609`](https://snowtrace.io/address/0xf580B985e2Fd8A8b0e4a56C2a7E24bC28e872609) | Role-based access control system            |

---

#### Monad (Mainnet)

The following contracts are deployed on Monad:

| Contract                     | Address                                                                                                                  | Description                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| **MultipliVault (xUSDC)**    | [`0xd74FB32112b1eF5b4C428Fead8dA8d85A0019009`](https://monadscan.com/address/0xd74FB32112b1eF5b4C428Fead8dA8d85A0019009) | Core vault contract for USDC deposits       |
| **VaultFundManager (xUSDC)** | [`0xE1824bF952bB2E8414d12de8A9fc2cBc666D6758`](https://monadscan.com/address/0xE1824bF952bB2E8414d12de8A9fc2cBc666D6758) | Manages fund movements and balance updates  |
| **VariableVaultFee (xUSDC)** | [`0xA39986F96B80d04e8d7AeAaF47175F47C23FD0f4`](https://monadscan.com/address/0xA39986F96B80d04e8d7AeAaF47175F47C23FD0f4) | Handles fee calculations and configurations |
| **RolesAuthority (xUSDC)**   | [`0x2A66Bb2dA3AD1c854E79307F64b862DECD860D4c`](https://monadscan.com/address/0x2A66Bb2dA3AD1c854E79307F64b862DECD860D4c) | Role-based access control system            |

---

### 4.2 Deployed Contracts (V2)

**Source Code:**  
[V2 branch](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2)

---

#### Avalanche C-Chain (Mainnet)

The following V2 contracts are deployed on Avalanche C-Chain:

| Contract                     | Address                                                                                                                 | Description                                 |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **MultipliVault (xWBTC)**    | [`0x468BbabAEf852C134b584382C0fef83F2954Cd5c`](https://snowtrace.io/address/0x468BbabAEf852C134b584382C0fef83F2954Cd5c) | Core vault contract for WBTC deposits       |
| **VaultFundManager (xWBTC)** | [`0x62c2181618833b202e68b5addc4279542978Ef47`](https://snowtrace.io/address/0x62c2181618833b202e68b5addc4279542978Ef47) | Manages fund movements and balance updates  |
| **VariableVaultFee (xWBTC)** | [`0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72`](https://snowtrace.io/address/0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72) | Handles fee calculations and configurations |
| **RolesAuthority (xWBTC)**   | [`0x2393D41EBc41270431Bdbdd3B3Ed03879636Ee42`](https://snowtrace.io/address/0x2393D41EBc41270431Bdbdd3B3Ed03879636Ee42) | Role-based access control system            |

---

## 5. Contract Overview

### 5.1 Core Contracts

1. **MultipliVault.sol**  
   This is the primary contract where users, fund managers, and oracles interact with the protocol. It serves as the main entry point and inherits functionality from multiple base contracts:

   - `ERC4626Upgradeable` - Provides standardized vault interface
   - `AuthUpgradeable` - Handles role-based access control
   - `PausableUpgradeable` - Emergency pause functionality
   - `VaultFeeUpgradeable` - Fee calculation and management
   - `FundMovementHelperUpgradeable` - Assists with fund transfers

2. **VaultFundManager.sol**  
   Manages all fund movements and balance updates within the protocol. This contract handles the actual movement of assets and invokes `onUnderlyingBalanceUpdate` in `MultipliVault`. Access control is enforced through the established Auth system in `MultipliVault`.

   To interact with this contract:

   - Use the `manage` method in MultipliVault to call methods in `VaultFundManager`
   - Methods in `VaultFundManager` then call back to MultipliVault as needed

   `VaultFundManager` also prevents sandwich attacks by ensuring that fund movements and balance updates happen atomically. This prevents attackers from exploiting temporary fluctuations in `totalAssets()` and `totalSupply()` to manipulate share prices and extract value during deposits or redemptions.

   ![Access Pattern for VaultFundManager](./docs/img/access-pattern.png)

3. **VariableVaultFee.sol**  
   Contains all fee calculation logic and is deployed as a separate contract from MultipliVault. This separation allows for flexible fee structures and independent upgrades. MultipliVault calls methods in this contract to calculate fees for various operations.

4. **RolesAuthority.sol**  
   Role-based access control system adapted from [Solmate](https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol). This contract manages permissions for different user roles within the protocol.

### 5.2 Deployment Scripts

The deployment scripts are located in `script/deployment/` and organized by environment:

- **Base.s.sol** - Abstract base contract providing common deployment functionality
- **mainnet/** - Production deployment scripts for Avalanche and Monad
- **testnet/** - Testnet deployment scripts
- **anvil/** - Local development deployment scripts

Each deployment script orchestrates the deployment process in the following order:

1. Deploys RolesAuthority contract
2. Deploys VariableVaultFee contract
   - Registers the underlying asset as an accepted asset
   - Sets fee rates for deposits and withdrawals
3. Deploys MultipliVault with UUPS Proxy
   - Configures the fee contract
   - Sets the authority contract
   - Makes the initial deposit to initialize the vault
   - Sets minimum deposit amounts
4. Deploys VaultFundManager contract
   - Assigns permissions for `FUND_MANAGER_ROLE` and `FUND_MANAGER_CONTRACT_ROLE`

## 6. User Roles

Roles are defined in [Role.sol](./src/common/Role.sol)

1. **FUND_MANAGER_ROLE**  
   Addresses with this role can invoke vault operations through the `VaultFundManager` contract using the `manage` method in `MultipliVault`. With the necessary permissions, they can also directly call the `updateUnderlyingBalance` method in `MultipliVault` to report changes in underlying asset positions. These addresses can perform the following operations:

   - `removeFundsFromVault`: Transfers assets from the vault to external strategies or exchanges
   - `updateUnderlyingBalance`: Updates the vault's view of assets held in external strategies
   - `addFundsAndFulfillRedeem`: Adds liquidity to the vault and processes pending redemption requests

2. **FUND_MANAGER_CONTRACT_ROLE**  
   The deployed `VaultFundManager` contract addresses are assigned this role. Addresses with this role can invoke critical vault operations including:

   - `onUnderlyingBalanceUpdate` - Updates the vault's view of underlying assets
   - `removeFunds` - Withdraws assets from the vault
   - `fulfillRedeem` - Processes pending redemption requests
   - `flashRedeem` - Flash redemption for unwinding leveraged positions

3. **ADMIN_ROLE**  
   Administrative permissions for managing the protocol configuration and user permissions.

# 7. Usage

## 7.1 Deposit Flow

Users can deposit assets using two standard ERC-4626 methods:

1. **`deposit(assets, receiver)`** - Deposit a specific amount of USDC to receive xUSDC shares
2. **`mint(shares, receiver)`** - Specify the amount of xUSDC shares you want to receive

Before depositing, we recommend using the preview methods to understand the transaction outcome:

**`previewDeposit(assets)`** - Input the amount of USDC you want to deposit. Returns the number of xUSDC shares you'll receive after fees are deducted. Note that front-running is possible, so the actual amount received may differ slightly.

**`previewMint(shares)`** - Input the number of xUSDC shares you want to receive. Returns the amount of USDC required after accounting for fees.

## 7.2 Withdrawal / Redemption Flow

Unlike standard ERC-4626 vaults, Multipli uses an asynchronous redemption system to accommodate the underlying investment strategies. Direct `redeem` and `withdraw` methods are not supported and will revert if called.

**Redemption Process:**

1. **Request Redemption** - Call `requestRedeem(shares)` to initiate a redemption request. This locks your shares for redemption.

2. **Processing Period** - Redemptions take 4-10 days to process. This timeframe allows the fund managers to unwind positions in the underlying strategies without negatively impacting returns.

3. **Fulfillment** - Fund managers call `fulfillRedeem` through the `VaultFundManager` contract to disburse USDC to user wallets.

**Preview Redemption** - Use `previewRedeem(shares)` to calculate the amount of USDC you'll receive for your xUSDC shares after fees.

## 7.3 FlashRedeem

### 7.3.1 What is FlashRedeem?

FlashRedeem is an advanced feature that allows authorized users to instantly convert their vault shares (like xUSDC) back to underlying assets (like USDC) within a single blockchain transaction. This is particularly useful for users who have their vault shares locked in external protocols (like lending platforms) and need to quickly unwind their positions.

Think of it as a "flash loan in reverse" - instead of borrowing assets and paying them back, you receive assets upfront and pay them back with equivalent shares.

### 7.3.2 Why Use FlashRedeem?

**Traditional Problem**: If you have 1,000 xUSDC shares but 800 of them are locked as collateral on a lending platform, you can't easily redeem them because you don't have all the shares in your wallet.

**FlashRedeem Solution**: The vault gives you USDC upfront, you use it to unlock your shares from the lending platform, then immediately return those shares to complete the redemption.

### 7.3.3 How to Use FlashRedeem

**Check Redemption Value**: Use `previewFlashRedeem(shares)` to see how much USDC you'll receive for your xUSDC shares after fees.

### 7.3.4 Key Players

- **Initiator**: The user who owns the shares and wants to redeem them
- **Operator Contract**: A smart contract that handles the complex unwinding logic (deployed by the initiator)
- **Multipli Admin**: The vault administrator who manages permissions and liquidity

### 7.3.5 Step-by-Step Process

#### Phase 1: Setup (One-time process)

1. **Request Access**: Initiator contacts the Multipli team to request FlashRedeem access
2. **Liquidity Provision**: Multipli team adds sufficient USDC to the VaultFundManager contract
3. **Authorization**: Multipli Admin whitelists the initiator and their operator contract using the vault's management system

#### Phase 2: Execution (Per redemption)

4. **Initiate FlashRedeem**: Initiator calls `VaultFundManager.flashRedeem()`
5. **Asset Transfer**: VaultFundManager transfers USDC to MultipliVault, then to the operator contract
6. **Position Unwinding**: Operator contract automatically:
   - Receives USDC from the vault
   - Uses USDC to repay debts and unlock collateral from external protocols
   - Collects the freed xUSDC shares
   - Returns the required amount of xUSDC shares back to the vault
7. **Completion**: System validates that the correct amount of shares were returned and the vault state is consistent

### 7.3.6 Technical Requirements

Your operator contract must implement the `IMultipliVaultCallee` interface, specifically the `onRedemptionFlashLoan()` method. This method is automatically called during the FlashRedeem process and must handle:

- Receiving the USDC from the vault
- Unwinding positions on external protocols
- Collecting and returning the equivalent xUSDC shares
- Ensuring all operations complete within the same transaction

### 7.3.7 Security Features

- **Whitelist Protection**: Only pre-approved initiator-operator combinations can use FlashRedeem
- **Atomic Execution**: Everything happens in one transaction - if any step fails, the entire operation reverts
- **State Validation**: Multiple checks ensure the vault remains in a consistent state after the operation
- **Fee Protection**: Appropriate fees are collected to prevent system abuse

### 7.3.8 Visual Flow

![Whitelist User-Operator Process](./docs/img/whitelist-user-operator-flow.png)

_Figure 1: The one-time setup process for authorizing users and operator contracts_

![FlashRedeem Contract Interaction](./docs/img/multipli-flashredeem-overview.png)

_Figure 2: Complete FlashRedeem execution flow showing all contract interactions_

### 7.3.9 Use Cases

- **Leveraged Position Unwinding**: Close complex leveraged positions across multiple protocols
- **Liquidity Management**: Quickly free up locked collateral without manual intervention
- **Arbitrage Opportunities**: Take advantage of price discrepancies across platforms
- **Emergency Exits**: Rapidly exit positions during market volatility

### 7.3.10 Example Implementation

```solidity
// Example operator contract implementing IMultipliVaultCallee
contract PositionUnwinder is IMultipliVaultCallee {
    function onRedemptionFlashLoan(
        address vault,
        address asset,
        address owner,
        address receiver,
        uint256 sharesToReturn,
        uint256 assetsReceived,
        bytes calldata data
    ) external override {
        // 1. Use received USDC to repay debts on lending protocol
        // 2. Withdraw xUSDC collateral from lending protocol
        // 3. Transfer required xUSDC shares back to vault
        // 4. Keep any excess for the user
    }
}
```

## 7.4 VaultFundManager: Operational Management Layer

### 7.4.1 Overview

The `VaultFundManager` serves as a dedicated operational layer that handles all critical vault maintenance activities. While `MultipliVault` technically has the capability to perform these operations directly, **all vault operations should be routed through `VaultFundManager`** to ensure proper state management and security.

### 7.4.2 Why Use VaultFundManager?

#### Atomic Operations & MEV Protection

`VaultFundManager` prevents sandwich attacks and MEV exploitation by ensuring that fund movements and balance updates happen atomically. This critical protection prevents attackers from:

- Exploiting temporary fluctuations in `totalAssets()` and `totalSupply()`
- Manipulating share prices during state transitions
- Extracting value through front-running deposits or redemptions

#### Consistent State Management

The fund manager ensures that all vault state changes maintain proper invariants and happen in the correct sequence, preventing inconsistencies that could arise from direct vault interactions.

### 7.4.3 Core VaultFundManager Activities

#### 1. Fund Removal (`removeFundsFromVault()`)

- **Purpose**: Transfer assets from vault to external strategies or exchanges
- **Key Feature**: Maintains `totalAssets()` invariant by updating aggregated underlying balances
- **Use Case**: Moving funds to trading strategies while preserving share price

#### 2. Balance Updates (`updateUnderlyingBalance()`)

- **Purpose**: Sync vault's understanding of assets held in external strategies
- **Key Feature**: Updates aggregated balances to reflect yield generation and strategy performance
- **Use Case**: Regular synchronization with external protocol positions

#### 3. Redemption Fulfillment (`addFundsAndFulfillRedeem()`)

- **Purpose**: Complete pending redemption requests by adding liquidity and processing withdrawals
- **Key Feature**: Three-step atomic process prevents price manipulation
- **Use Case**: Settling user withdrawal requests after bringing funds back from strategies

### 7.4.4 Access Pattern

#### Recommended Flow

```
User/Operator → MultipliVault.manage() → VaultFundManager.method() → MultipliVault (callback)
```

#### How It Works

1. **Authorization**: Use `MultipliVault.manage()` method to call `VaultFundManager` functions
2. **Execution**: `VaultFundManager` performs the requested operation
3. **Callback**: `VaultFundManager` calls back to `MultipliVault` as needed to update state
4. **Validation**: Built-in checks ensure state consistency throughout the process

#### Security Benefits

- **Single Entry Point**: All operations go through vault's authorization system
- **Atomic Execution**: Complex multi-step operations happen in single transaction
- **State Validation**: Automatic verification of vault invariants
- **MEV Protection**: Prevents exploitation of temporary state inconsistencies

### 7.4.5 Integration Examples

#### Moving Funds to Exchange

```solidity
// Move 100,000 USDC to external exchange
vault.manage(
    address(fundManager),
    abi.encodeWithSelector(
        VaultFundManager.removeFundsFromVault.selector,
        exchangeAddress,
        100000e6
    ),
    0
);
```

#### Updating Strategy Yields

```solidity
// Update vault with new strategy balances (including yield)
vault.manage(
    address(fundManager),
    abi.encodeWithSelector(
        VaultFundManager.updateUnderlyingBalance.selector,
        newTotalBalance
    ),
    0
);
```

#### Fulfilling User Redemptions

```solidity
// Fulfill pending redemption after bringing funds back
vault.manage(
    address(fundManager),
    abi.encodeWithSelector(
        VaultFundManager.addFundsAndFulfillRedeem.selector,
        userAddress,
        sharesAmount,
        assetsAmount
    ),
    0
);
```

### 7.4.6 Visual Flow

![Access Pattern for VaultFundManager](./docs/img/access-pattern.png)
_Figure 1: Recommended access pattern showing secure operation flow through vault's manage function_

![Example Contract Interaction for VaultFundManager Methods](./docs/img/eg-flows.png)
_Figure 2: Detailed example flows showing how different operations are executed through VaultFundManager_

### 7.4.7 Best Practices

- **Always use `MultipliVault.manage()`** to call VaultFundManager methods
- **Never call VaultFundManager methods directly** from external contracts

### 7.4.8 Security Considerations

- **Authorization Required**: All operations require proper vault-level permissions
- **State Invariants**: Fund manager enforces critical vault invariants during operations
- **Atomic Execution**: Operations either complete fully or revert entirely
- **MEV Protection**: Built-in safeguards against value extraction attacks

---

**Important**: While `MultipliVault` can technically perform these operations directly, using `VaultFundManager` is **strongly recommended** for security, consistency, and MEV protection.

## 8. Known Issues

1. ### Yield Distribution Exploit

   Attackers can exploit Yield distribution through `onUnderlyingBalanceUpdate` Sandwiching

   **Scenario:** When operators call `onUnderlyingBalanceUpdate` to report the yield generated, attackers can front-run this transaction with a large deposit transaction, capturing a disproportionate share of the yield update and then immediately withdraw their position.

   **Solution Implemented:** Instead of updating the underlying balance all at once, the onUnderlyingBalanceUpdate function is triggered every 8 hours over a 7-day period, totaling 21 updates per week. This staggered approach distributes yield updates more evenly and helps prevent potential exploitation by malicious users

2. ### Fee Inconsistency in Redemptions

   There's a potential inconsistency between `requestRedeem` and `fulfillRedeem` operations due to fee changes:

   **Scenario:** A user initiates a redeem request when the fee is 100 USDC. Before the redemption is fulfilled, the fee configuration is updated.

   - **If fee increases:** User receives less than initially previewed
   - **If fee decreases:** User receives more than initially previewed

   **Mitigation:** Fund managers can invoke `cancelRedeem` when there's a significant fee mismatch, allowing users to reinitiate their redemption request with current fee rates.

3. ### Asset/Share Mismatch in fulfillRedeem

   When fund managers call `fulfillRedeem`, there's a possibility of specifying incorrect asset amounts for the corresponding shares.

   **Example:** User requests redemption of 100 shares worth 100 USDC. During fulfillment, admin might incorrectly specify 100 shares with only 50 USDC or vice versa.

   **Impact:** These mismatched assets/shares will remain in `_pendingRedeem` state. The backend system should implement validation to prevent such discrepancies.

4. ### Temporary Share Price Impact During Pending Redemptions

   **Issue**:  
   Asynchronous redemption processing can cause temporary share price flunctuations when underlying balances are updated between `requestRedeem` and `fulfillRedeem` calls.

   **Root Cause:**  
    When users call `requestRedeem()`, shares are transferred to the vault but `totalSupply` and `totalAssets` remain unchanged until `fulfillRedeem()` is executed. If `updateUnderlyingBalance()` occurs during this pending period, it affects the share price calculation for all remaining shareholders.

   **Scenario 1: Underlying Assets Increase**

   ```
   Initial State:
      - totalSupply: 1,000 shares
      - totalAssets: 1,000 USDC
      - Price: 1 USDC per share

      1. User requests redemption of 100 shares (100 USDC value)
      2. updateUnderlyingBalance() increases totalAssets 1,100 USDC
         - New price: 1.1 USDC per share
      3. fulfillRedeem() executed:
         - User receives: 100 USDC (original redemption value)
         - 100 shares burned
         - Final state: 900 shares, 1,000 USDC
         - **Result: Price increases to 1.111 USDC per share**

   ```

   **Scenario 2: Underlying Assets Decrease**

   ```
   Initial State:
      - totalSupply: 1,000 shares
      - totalAssets: 1,000 USDC
      - Price: 1 USDC per share

      1. User requests redemption of 100 shares (100 USDC value)
      2. updateUnderlyingBalance() decreases totalAssets to 900 USDC
         - New price: 0.9 USDC per share
      3. fulfillRedeem() executed:
         - User receives: 100 USDC (original redemption value)
         - 100 shares burned
         - Final state: 900 shares, 800 USDC
         - **Result: Price decreases to 0.889 USDC per share**
   ```

   **Impact**:

   - Severity: Low - No funds are lost, only timing of profit/loss recognition
   - Effect: Remaining shareholders experience delayed reflection of actual vault performance
   - Duration: Temporary until all pending redemptions are fulfilled

   **Potential Solutions:**

   - Exclude pending shares from price calculations: effectiveSupply = totalSupply - pendingShares
   - Trade-off: Could cause price volatility if redemptions are cancelled

   **Current Status**:

   Accepted as design limitation - vault performance is eventually accurate once redemptions are processed and increase in price can be attributed an additional yield.

## 9. Backend Monitoring and Operations

The backend system performs critical monitoring and maintenance tasks:

1. **Event Monitoring:** All events from the following contracts are tracked:

   - MultipliVault
   - VariableVaultFee
   - RolesAuthority
   - VaultFundManager

2. **Sweep Funds:** When vault's USDC balance crosses a certain threshold (e.g., 10,000 USDC), fund manager invokes `VaultFundManager.removeFundsFromVault` method to move the funds to exchanges/strategies.

3. **Balance Updates:** Periodically calls `onUnderlyingBalanceUpdate` with the latest asset values from underlying strategies.

4. **Redemption Processing:** Tracks `requestRedeem` requests to ensure funds are disbursed within the 4-10 day window.

5. **Fee Change Management:** Monitors fee changes between `requestRedeem` and `fulfillRedeem`, canceling requests when significant mismatches occur.

6. **Safety Mechanisms:** If the percentage difference exceeds `maxPercentageChange` in `onUnderlyingBalanceUpdate`, the contract is automatically paused and alerts are triggered. Monitor for `Paused` events.

7. **Fee Contract Management:** The fee contract can be set to `address(0)` if needed. The system emits `FeeContractUpdated` events whenever the fee contract is modified in MultipliVault.

## 10. Version 2

For enhanced features including multi-chain support and additional deployed vaults, please refer to the [V2 branch](https://github.com/multipli-libs/Barebones-MultipliVault/tree/v2).
