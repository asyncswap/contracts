# AsyncOrder

[Git Source](https://github.com/asyncswap/contracts/blob/16b469f37d1b441e4bdde50c26d9dc0c32b018c1/src/types/AsyncOrder.sol)

Represents an async order for a swap in the Uniswap V4 pool.

```solidity
struct AsyncOrder {
    PoolKey key;
    address owner;
    bool zeroForOne;
    uint256 amountIn;
    uint256 amountOutMin;
    uint256 priorityFee;
    uint160 sqrtPrice;
    bytes32 salt;
}
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` | The Uniswap V4 PoolKey identifying the pool the order is placed against. |
| owner | `address` | The maker who supplied `amountIn` of the input currency at order submission. |
| zeroForOne | `bool` | Direction of the order. true => input is currency0, output is currency1. |
| amountIn | `uint256` | Amount of input currency the maker escrowed. Direct matching may partially fill it;<br />unused input is returned when the maker's minimum output is satisfied. |
| amountOutMin | `uint256` | Minimum amount of output currency the maker accepts. The implicit limit price is<br />`amountOutMin / amountIn`. A filler or direct match must satisfy the live minimum<br />for the amount it consumes. |
| priorityFee | `uint256` | Non-refundable USDC bid for equal-price priority. Priority-fee mode requires at<br />least $0.10; filled portions are donated to active LPs, and any remainder is<br />donated when canceled or moved to the protocol FeeVault if no LPs are active. |
| sqrtPrice | `uint160` | Sqrt-price limit passed to `PoolManager.swap` on submission. The hook consumes<br />the whole input in `beforeSwap`, so the pool never trades against it. |
| salt | `bytes32` | Contract-assigned salt that disambiguates orders. The hook computes this at create<br />time from `keccak256(timestamp, block.number, msg.sender, owner, amountIn,<br/>amountOutMin, priorityFee)` and emits it in `AsyncOrderCreated` so the maker can reference the<br />order in cancel / updatePrice. Submitters pass `bytes32(0)` on create — the value<br />in this slot is only read on cancel / updatePrice / fill paths. |
