# HUBSVULT — Multipli Protocol V2

## Project Overview
ERC-4626 compatible vault protocol for Real World Asset (RWA) yield via delta-neutral strategies. Deployed on Avalanche C-Chain with UUPS proxy upgradeability.

## Agent Priorities
- Preserve upgradeability safety first: avoid storage layout drift, initializer mistakes, and unsafe UUPS changes.
- Preserve the vault execution model: operators should interact through `MultipliVault.manage()` unless a test is intentionally verifying unauthorized access.
- Prefer minimal, targeted edits over broad refactors.
- When changing accounting, redemption, or fee logic, verify invariants with focused tests before broader test runs.
- Treat `VaultFundManager`, `FlashLoanExecutor`, and `TimelockGuardian` as high-sensitivity components.

## Tech Stack
- **Solidity 0.8.34** (pinned pragma across all files)
- **Foundry** (forge, cast, anvil) — build, test, deploy
- **OpenZeppelin Contracts Upgradeable v5.3.0** — ERC4626, UUPS, Pausable
- **Solmate** — RolesAuthority (access control)
- **Node.js v22** — for `@openzeppelin/upgrades-core` (upgrade safety checks)

## Repository Layout
```
src/
  vault/MultipliVault.sol        — Core ERC-4626 vault (UUPS upgradeable)
  managers/VaultFundManager.sol  — Fund movement + MEV protection layer
  managers/FlashLoanExecutor.sol — Flash loan orchestration helper
  fees/VariableVaultFee.sol      — Fee calculation (separate contract)
  migrator/MultipliMigrator.sol  — V1→V2 migration (not deployed)
  base/                          — Upgradeable base contracts (Auth, Fees, FundMovement)
  common/Role.sol                — Role constants
  interfaces/                    — Contract interfaces
  libraries/Errors.sol           — Custom errors
  security/TimelockGuardian.sol  — Timelocked admin/guardian wrapper for sensitive ops
test/
  unit/vault/                    — Vault unit tests
  unit/managers/                 — VaultFundManager tests
  unit/migrator/                 — Migrator tests
  unit/fees/                     — Fee tests
  unit/security/                 — Timelock/security tests
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
NETWORK=avalanche TOKEN=usdc ENV=mainnet forge test --match-path "test/unit/security/*" -vvvv

# Run a focused contract or test name:
forge test --match-contract MultipliVaultTest -vvvv
forge test --match-test test_RequestRedeem_RevertsWhen* -vvvv

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

## High-Risk Components & Invariants
- **`MultipliVault.sol`**
  - Preserve ERC-4626 semantics unless intentionally documenting a divergence.
  - `withdraw()` and `redeem()` are intentionally disabled in favor of async redemption.
  - `manage()` must continue to enforce authority checks on target + selector.
- **`VaultFundManager.sol`**
  - Functions are generally intended to be reached via the vault's `manage()` flow.
  - Preserve `onlyVault` boundaries and `nonReentrant` placement.
  - Be careful with `aggregatedUnderlyingBalances`, withdrawal caps, and fulfill/remove-funds accounting.
- **`VariableVaultFee.sol`**
  - Shared across vaults on the same network; changes can have multi-vault blast radius.
- **`TimelockGuardian.sol`**
  - Guardian/admin separation is security-critical; preserve emergency pause and cancellation semantics.
- **`FlashLoanExecutor.sol`**
  - Treat callback validation, repayment checks, and external call ordering as security-sensitive.

## Upgradeability & Storage Safety
- Do not reorder, delete, or repurpose existing storage variables.
- Prefer append-only storage changes inside upgradeable storage structs / namespaces.
- Keep initializer and reinitializer flows consistent with OZ upgradeable patterns.
- If a change touches storage, auth, pause, or upgrade logic, inspect generated `storageLayout` output before concluding the change is safe.
- Avoid introducing constructors in upgradeable implementation contracts.

## Editing Guardrails
- Use absolute imports only.
- Prefer custom errors and `if/revert` checks.
- Prefer `calldata` for read-only external inputs.
- Keep function ordering and section headers aligned with the established Cyfrin layout.
- Avoid speculative refactors in `src/`; pair behavior changes with focused test updates.

## Preferred Validation Workflow
1. Run the smallest relevant test target first.
2. If the change touches shared accounting, run the whole affected folder.
3. Run `forge build` after Solidity changes.
4. Use `npm run test` only when the change needs matrix-wide confidence.

Suggested progression:
- single test via `--match-test`
- single contract via `--match-contract`
- single folder via `--match-path`
- `forge build`
- `npm run test` when cross-network / cross-token behavior may differ

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
- **Floating pragma** for interfaces, libraries, and abstract contracts (`^0.8.34`)
- **Pinned pragma** for concrete contracts (`0.8.34`)
- **`calldata` over `memory`** for read-only function inputs
- **`@custom:security-contact security@multipli.com`** on all contracts
- **Absolute imports only** — no relative `..` paths

## Known Issues (accepted design tradeoffs)
1. Yield distribution sandwiching mitigated by staggered `onUnderlyingBalanceUpdate` (21 updates/week)
2. Fee inconsistency between requestRedeem/fulfillRedeem — mitigated by admin cancelRedeem
3. Asset/share mismatch in fulfillRedeem — backend validation required
4. Temporary share price impact during pending redemptions — accepted as eventual consistency

## Common Pitfalls For Agents
- Do not call `VaultFundManager` directly in normal flows; go through `MultipliVault.manage()`.
- Do not re-enable synchronous `withdraw()` / `redeem()` unless the protocol design is intentionally changing.
- Do not treat fee logic as vault-local without checking the shared fee contract impact.
- Do not make upgradeability-affecting changes without checking storage and initializer safety.
- Do not assume a test passes globally because it passes on the default Avalanche/USDC config.
