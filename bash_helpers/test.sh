#!/usr/bin/env bash
set -e

# Define valid combinations (ENV NETWORK TOKEN)
COMBINATIONS=(
  "mainnet ethereum usdc"
  "testnet ethereum usdc"
  "mainnet ethereum wbtc"
  "testnet ethereum wbtc"
  "mainnet bsc usdc"
  "testnet bsc usdc"
  "mainnet bsc wbtc"
  "testnet bsc wbtc"
  "mainnet avalanche usdc"
  "testnet avalanche usdc"
  "testnet avalanche btc.b"
  "mainnet avalanche btc.b"
)

# Folders to test per combination
COMBO_FOLDERS=(
  "test/unit/vault/*"
  "test/unit/managers/*"
  "test/unit/migrator/*"
  "test/unit/fees/*"
)

# Folders to test once at the end
NON_CONFIG_FOLDERS=(
  
  "test/unit/deployment/*"
)

echo "-------------------------------------------------"
echo "Compiling all contracts first..."
echo "-------------------------------------------------"
forge clean && forge build

# Loop over combinations
for combo in "${COMBINATIONS[@]}"; do
  read -r ENV NETWORK TOKEN <<< "$combo"

  echo "-------------------------------------------------"
  echo "Running test for ENV=$ENV NETWORK=$NETWORK TOKEN=$TOKEN"
  echo "-------------------------------------------------"

  # Run tests for each folder individually
  for folder in "${COMBO_FOLDERS[@]}"; do
    set +e
    ENV=$ENV NETWORK=$NETWORK TOKEN=$TOKEN forge test --match-path "$folder" "$@"
    STATUS=$?
    set -e
    if [ $STATUS -ne 0 ]; then
      echo "❌ Test failed for combination: ENV=$ENV NETWORK=$NETWORK TOKEN=$TOKEN in folder $folder"
      exit $STATUS
    fi
  done
done

# Run non-config tests once at the end
echo "-------------------------------------------------"
echo "Running Non Config Tests"
echo "-------------------------------------------------"
for folder in "${NON_CONFIG_FOLDERS[@]}"; do
  forge test --match-path "$folder" "$@"
done

echo "✅ All tests passed for all valid combinations!"
