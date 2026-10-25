# Batch actions on Unichain

`BatchActions` cancels a maker's open Async Swap orders, redeems their PoolManager ERC-6909 balances, or does both in one transaction and one PoolManager unlock. The contract is specific to the deployed Async Swap hook; a general public multicall contract cannot act as the maker's authorized hook executor or as the maker's PoolManager operator.

## Deploy with a Foundry keystore

From the `contracts` directory, set the existing Unichain mainnet hook and run:

```sh
export HOOK_ADDRESS=0x917b2e7C352af82c35C7a4477d7D055C54E76888
forge script script/DeployBatchActions.s.sol:DeployBatchActions \
  --rpc-url https://mainnet.unichain.org \
  --account YOUR_FOUNDRY_KEYSTORE \
  --broadcast
```

Foundry prompts for the keystore password. The script checks chain ID 130, confirms the hook and canonical PoolManager have code, and confirms the hook uses that PoolManager. Run the same command without `--broadcast` first to simulate. The deploy command creates only `BatchActions`; it does not change the hook, Router, or PoolManager.

Record the deployed address from the Foundry receipt before enabling the interface controls.

## Maker approvals

Each maker must authorize the deployed helper before using its actions:

- For each order pool, call `AsyncSwap.setExecutor(poolId, BATCH_ACTIONS_ADDRESS, true)` from the maker wallet. The hook checks this permission during cancellation.
- For ERC-6909 redemption, call `PoolManager.setOperator(BATCH_ACTIONS_ADDRESS, true)` from the maker wallet. PoolManager checks this permission when the helper burns the maker's claims.

Both permissions can be revoked by calling the same methods with `false`. They are independent: cancelling does not require PoolManager operator approval, and redeeming does not require hook executor approval.

`execute(orders, currencies, amounts, recipient)` takes the complete order structs and matching claim arrays. Use empty arrays for an action you do not want. Native ETH is currency `address(0)`; ERC20 currencies use their token addresses. The helper refuses orders owned by another wallet, duplicate claim currencies, zero claim amounts, and batches over 50 orders or 16 currencies. An execution reverts in full if any cancel or redemption fails. Large batches may still exceed the network gas limit; split them when needed.

Do not submit `--private-key` in a command history or send a key to the interface. Use a Foundry keystore or hardware signer.
