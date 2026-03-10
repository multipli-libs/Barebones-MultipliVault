# HUBSVULT — Multipli Protocol V2

## Project Overview
ERC-4626 compatible vault protocol for Real World Asset (RWA) yield via delta-neutral strategies. Deployed on Avalanche C-Chain with UUPS proxy upgradeability.

## Tech Stack
- **Solidity 0.8.34** (pinned pragma across all files)
- **Foundry** (forge, cast, anvil) — build, test, deploy
- **OpenZeppelin Contracts Upgradeable v5.3.0** — ERC4626, UUPS, Pausable
- **OpenZeppelin Contracts v5.3.0** — core modules via additional OZ remappings
- **Solmate** — RolesAuthority (access control)
- **Solady** — gas-optimised primitives via remappings
- **Node.js v22** — for `@openzeppelin/upgrades-core` (upgrade safety checks)

## Repository Layout
```
src/
  vault/MultipliVault.sol        — Core ERC-4626 vault (UUPS upgradeable)
  managers/VaultFundManager.sol  — Fund movement + MEV protection layer
  fees/VariableVaultFee.sol      — Fee calculation (separate contract)
  migrator/MultipliMigrator.sol  — V1→V2 migration (not deployed)
  base/                          — Upgradeable base contracts (Auth, Fees, FundMovement)
  common/Role.sol                — Role constants
  interfaces/                    — Contract interfaces
  libraries/Errors.sol           — Custom errors
test/
  unit/vault/                    — Vault unit tests
  unit/managers/                 — VaultFundManager tests
  unit/migrator/                 — Migrator tests
  unit/fees/                     — Fee tests
  unit/deployment/               — Contract size / deployment tests
  mocks/                         — Mock contracts
  utils/                         — ConfigLib, Constants, Events, Types, Utils
  BaseNetworkTokenConfig.t.sol   — Multi-chain/token test config base
script/deployment/               — Deploy scripts (Base.s.sol, BaseWithSharedConfig.s.sol)
```

## Build & Test Commands
```bash
forge build                    # Compile
forge test -vvvv               # Run tests (defaults: NETWORK=avalanche ENV=mainnet TOKEN=usdc)

# Run with specific config:
NETWORK=ethereum TOKEN=wbtc ENV=testnet forge test --match-path "test/unit/vault/*" -vvvv

# Run ALL test combinations (12 configs × 4 folders + deployment):
npm run test
```

## Test Matrix
Tests run across 12 network/token/env combinations via `bash_helpers/test.sh`:
- Networks: `ethereum`, `bsc`, `avalanche`
- Tokens: `usdc`, `wbtc`, `btc.b` (avalanche only)
- Envs: `mainnet`, `testnet`

Config-dependent folders: `test/unit/vault/*`, `test/unit/managers/*`, `test/unit/migrator/*`, `test/unit/fees/*`
Config-independent: `test/unit/deployment/*` (runs once)

## Key Architecture Patterns
- **UUPS Proxy**: Vault is upgradeable; deploy scripts use OZ Foundry Upgrades
- **manage() pattern**: External callers → `MultipliVault.manage()` → `VaultFundManager` → callbacks to vault. Never call VaultFundManager directly.
- **Async redemptions**: `requestRedeem()` → 4-10 day wait → `fulfillRedeem()` via fund manager
- **Shared fee contract**: One `VariableVaultFee` per network, shared across all vaults
- **Role-based access**: FUND_MANAGER_ROLE, FUND_MANAGER_CONTRACT_ROLE, ADMIN_ROLE, ETHEREUM_MIGRATOR_V1

## Remappings (remappings.txt)
```
@openzeppelin/contracts/=lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@solmate/=lib/solmate/src/
forge-std/=lib/forge-std/src/
```

## Deployment
- First vault on a network: `Base.s.sol` (deploys new VariableVaultFee)
- Additional vaults: `BaseWithSharedConfig.s.sol` (reuses existing fee contract)
- RPC endpoints configured in foundry.toml: `avax_mainnet`, `avax_testnet`, `anvil`
- Verification via RouteScan API

## Code Style (foundry.toml [fmt])
- Line length: 100
- Tab width: 4
- Bracket spacing: `{ }` not `{}`
- Int types: `uint256` (long form)
- Number underscore: thousands (`1_000_000`)
- Double quotes for strings
- fmt ignores test/ and script/ directories

## Cyfrin Solidity Standards (applied)
All source files follow [Cyfrin development standards](https://www.cyfrin.io/):
- **Error naming**: `ContractName__ErrorName` — e.g., `VaultFundManager__ZeroAddress()`, `Errors__InsufficientShares()`, `IVariableVaultFee__InvalidAsset()`
- **Headers**: `/*//////////////...*/` section headers for TYPE DECLARATIONS, STATE VARIABLES, EVENTS, ERRORS, MODIFIERS, and function visibility groups
- **Contract layout**: types → state → events → errors → modifiers → functions
- **Function ordering**: constructor → receive/fallback → external/public state-changing → external/public view → internal state-changing → internal view → private
- **`if/revert` over `require`**: All validation uses `if (cond) revert ContractName__Error()`
- **`nonReentrant` before other modifiers**: e.g., `nonReentrant onlyVault`
- **Floating pragma** for interfaces, libraries, and abstract contracts (`^0.8.30`)
- **Pinned pragma** for concrete contracts (`0.8.30`)
- **`calldata` over `memory`** for read-only function inputs
- **`@custom:security-contact security@multipli.com`** on all contracts
- **Absolute imports only** — no relative `..` paths

## Known Issues (accepted design tradeoffs)
1. Yield distribution sandwiching mitigated by staggered `onUnderlyingBalanceUpdate` (21 updates/week)
2. Fee inconsistency between requestRedeem/fulfillRedeem — mitigated by admin cancelRedeem
3. Asset/share mismatch in fulfillRedeem — backend validation required
4. Temporary share price impact during pending redemptions — accepted as eventual consistency
