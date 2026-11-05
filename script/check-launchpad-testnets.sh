#!/usr/bin/env bash
set -euo pipefail
# Read-only remote calls; all deployments/trades happen in ephemeral local forks.
LAUNCHPAD_TESTNET_RPC="${RPC_URL_ROBINHOOD_TESTNET:-https://rpc.testnet.chain.robinhood.com}" \
  forge test --match-contract LaunchpadTestnetTest --match-test 'test_supplyAndPositionAreLocked|test_buyAndClaimFeesNeverWithdrawPrincipal|test_multipleLaunchesSortBeforeNumeraire' -vv
LAUNCHPAD_TESTNET_RPC="${RPC_URL_UNICHAIN_SEPOLIA:-https://sepolia.unichain.org}" \
  forge test --match-contract LaunchpadTestnetTest --match-test 'test_supplyAndPositionAreLocked|test_buyAndClaimFeesNeverWithdrawPrincipal|test_multipleLaunchesSortBeforeNumeraire' -vv
