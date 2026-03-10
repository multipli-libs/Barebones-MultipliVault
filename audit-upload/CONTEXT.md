# Multipli Protocol V2 — Audit Context

## Overview
ERC-4626 compatible vault protocol for Real World Asset (RWA) yield via delta-neutral strategies. Deployed on Avalanche C-Chain with UUPS proxy upgradeability.

## Architecture

### Core Flow
1. Users deposit USDC into `MultipliVault` (ERC-4626) and receive shares
2. Fund manager moves assets off-chain via `VaultFundManager` for RWA yield strategies
3. Yield is reflected by updating `underlyingBalance` (async, ~21 updates/week)
4. Users request redemptions (async: 4-10 day wait) then claim via `fulfillRedeem`

### Delegation Pattern (`manage()`)
All external management operations go through `MultipliVault.manage()` which delegatecalls or calls into authorized manager contracts (e.g., `VaultFundManager`). The fund manager then calls back into the vault to move funds. Direct calls to VaultFundManager revert unless caller is the vault.

### Access Control
- `RolesAuthority` (Solmate) — role-based permissions
- Key roles: `FUND_MANAGER_ROLE` (operators), `FUND_MANAGER_CONTRACT_ROLE` (VaultFundManager contract), `ADMIN_ROLE`
- `TimelockGuardian` — 48-hour timelock for critical admin operations, guardian can cancel or emergency pause

### Withdrawal Cap (Epoch-Based)
- `VaultFundManager` enforces per-epoch (24h) withdrawal limits via `maxWithdrawalPerEpoch`
- Shared counter across both `removeFundsFromVault()` and `removeFunds()`
- Epoch resets when `block.timestamp > lastEpochReset + 24 hours`
- Cap of 0 = disabled (no limit)

### MEV Protection
- `VaultFundManager` uses block-number checks to prevent same-block deposit+withdraw sandwiching
- Admin mint/burn capped at 1,000,000 tokens per operation

### Fee Structure
- `VariableVaultFee` — separate contract, shared across vaults on a network
- Performance fee + management fee, calculated on `previewRedeem`/`previewWithdraw`

## Upgradeability
- UUPS proxy pattern (OpenZeppelin v5.3.0)
- `_authorizeUpgrade` restricted to admin role
- Storage gaps in all base contracts

## Trust Assumptions
- Admin/operators are trusted (multisig in production)
- `underlyingBalance` updates are trusted (off-chain oracle)
- Users trust the 4-10 day async redemption window

## Contracts NOT deployed yet (review for completeness)
- `FlashLoanExecutor.sol` — flash loan strategy execution (unfinished, needs security hardening)
- `MultipliMigrator.sol` — V1 to V2 migration helper (not deployed)
- `TimelockGuardian.sol` — newly added, not yet integrated into deployment

## Known Design Tradeoffs
1. Yield distribution sandwiching — mitigated by staggered underlyingBalance updates
2. Fee inconsistency between requestRedeem/fulfillRedeem — mitigated by admin cancelRedeem
3. Asset/share mismatch in fulfillRedeem — backend validation required
4. Temporary share price impact during pending redemptions — accepted as eventual consistency

## Solidity Version
0.8.34 with EVM target: Cancun (EIP-1153 transient storage available)
