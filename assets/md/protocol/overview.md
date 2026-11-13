# Async Swap protocol

Async Swap is a Uniswap v4 hook that turns exact-input swaps into resting limit orders. The hook uses v4
custom accounting (`beforeSwapReturnDelta`) to take the whole swap input as an order, and v4 flash accounting
(one `PoolManager.unlock` per action, every delta zero at the end) to settle matches, fills and fees. Orders
are good till cancelled (GTC): there is no expiry, so an order rests until it fills or the maker cancels it.

This page is the entry point. It shows the contracts, where funds sit, how an order is placed, and who may do
what. Every box names a contract, library or function in `src/`, so the diagrams can be checked against the code.

## Guides

| Guide | Covers |
|---|---|
| [Order lifecycle and priority bids](/protocol/order-lifecycle) | Create, match, reprice, top up, cancel; bid settlement |
| [Flash fills and non-numeraire pools](/protocol/flash-fills) | `fillOrderWithCallback`, nested `fillOrderInCallback`, the per-fill MEV tax, pools without USDC |
| [Dutch auction orders](/protocol/dutch-auction) | `startAuction`, steps, fills |
| [Contract call sequences](/protocol/contract-call-sequences) | Step-by-step calls for placement, fills, cancels, setup and withdrawals |
| [Priority fee top-ups](/protocol/priority-fee-top-ups) | `topUpPriorityFee` and agent batching |
| [Signed price changes](/protocol/repricing-signatures) | `UpdatePrice` and `CancelOrder` typed data |
| [Price keys and crossing](/protocol/price-key-crossing) | How limit prices become v4 tick keys and when two orders cross |
| [Dynamic fee ordering](/protocol/dynamic-fee-ordering) | How pool-fill backruns pay LPs and the protocol |
| [Deployments](/deployments) | Addresses per chain |

## 1. Components

```mermaid
flowchart LR
    subgraph Actors
        Maker["Maker"]
        Relayer["Relayer<br/>(signed orders, cancels)"]
        Filler["Filler<br/>(EOA or flash-filler contract)"]
        Anyone["Anyone<br/>(matchBook, fillFromPoolLiquidity,<br/>pool setup)"]
        LP["v4 LP"]
        Owner["Protocol owner"]
    end

    subgraph Periphery
        Router["Router<br/>swap · swapWithSig · fillOrder<br/>cancelOrder · cancelWithSig · cancelAndWithdraw<br/>withdrawClaims · topUpPriorityFee<br/>matchBook · fillFromPoolLiquidity · multicall<br/>mevTax"]
        RFF["RouterFlashFills<br/>fillOrderWithCallback · fillOrderInCallback<br/>matchBookInCallback · mevTaxFor · mevTaxOwed"]
        Base["AsyncSwapFlashFiller<br/>abstract base: write _route"]
        Permit2["Permit2"]
        Claims["NativeClaims · TokenClaims"]
    end

    subgraph Core
        PM["Uniswap v4 PoolManager<br/>unlock · swap · ERC-6909 claims"]
        Hook["AsyncSwap hook<br/>beforeInitialize · beforeSwap · beforeAddLiquidity<br/>matchNewOrder · executeOrder · flashFill<br/>updatePrice(WithSig) · startAuction · auctionPremium<br/>cancelOrder · matchBook · tryFillOrderFromPoolLiquidity"]
        Libs["Linked libraries<br/>(see section 5)"]
        Vault["FeeVault<br/>collect(currency, recipient)"]
    end

    Maker -->|orders, cancels, claims| Router
    Maker -->|setExecutor, updatePrice, startAuction| Hook
    Relayer -->|swapWithSig, cancelWithSig| Router
    Relayer -->|updatePriceWithSig| Hook
    Filler -->|fillOrder| Router
    Filler -->|fill| Base
    Base -->|fillOrderWithCallback| Router
    Router -.->|fallback: DELEGATECALL| RFF
    Anyone -->|matchBook, fillFromPoolLiquidity| Router
    LP -->|modifyLiquidity| PM
    Owner -->|collect| Vault

    Router -->|unlock| PM
    Router -->|signed input| Permit2
    PM -->|beforeSwap| Hook
    Router -->|hook entry points| Hook
    Hook -.->|DELEGATECALL| Libs
    Hook -->|take · mint · burn · settle · swap| PM
    Vault -->|burn + take| PM
    Maker -->|redeem| Claims
    Claims -->|burn + take| PM
```

Anyone may open a pool on the hook with the dynamic-fee flag. A pool that holds the chain's USDC (`numeraire`)
opens freely. A pool without it, such as ETH/TOKEN, opens once both tokens already have a numeraire pool on this
hook with the same tick spacing; see [non-numeraire pools](/protocol/flash-fills#non-numeraire-pools).

Each order must meet two floors, fixed when the pool opens:

* **Minimum order** on the quote leg: USDC on a numeraire pool, from the constructor's whole-dollar
  minimum scaled by `decimals()`.
* **Asset floor** on the other leg: `10^(decimals - assetPrecision)` base units (0.0001 token with the
  deployed precision of 4). Native ETH counts as 18 decimals; an asset with no code is rejected.

No check reads a price, and nothing has a setter, so the owner cannot change the rules under live orders.
`beforeAddLiquidity` is a pass-through: ordinary v4 range positions are the inventory for pool fills. No user
swap reaches the AMM curve directly, because `beforeSwap` takes the whole input as an order. The standalone
`MatchingEngine.sol` is a benchmark harness and is not deployed.

## 2. Where funds live

```mermaid
flowchart TB
    subgraph PoolManager["PoolManager (custody)"]
        Escrow["Hook claims<br/>= open orders' remaining input<br/>+ escrowed priority bids"]
        Fees["FeeVault claims<br/>trade fees · pool-fill fees<br/>half of each dynamic fee<br/>settled bids · MEV tax (native)"]
        User["Maker and filler claims<br/>match proceeds, refunds,<br/>native payouts, flash-fill input"]
        Reserves["Pool reserves<br/>v4 LP positions"]
    end
    MakerW["Maker wallet"] -->|input on swap| Escrow
    Escrow -->|cancel| MakerW
    Escrow -->|book match| User
    Escrow -->|filler fill| FillerW["Filler wallet"]
    Escrow -->|flash fill: input as claims| User
    FillerW -->|fill: output| MakerW
    Escrow -->|fees, bids| Fees
    Reserves -->|pool fill output| MakerW
    Reserves -->|dynamic fee: half| Fees
    Fees -->|collect| OwnerW["Owner-chosen recipient"]
    User -->|TokenClaims / NativeClaims /<br/>Router.withdrawClaims| MakerW
```

| Fee | Rate | Paid by | Event |
|---|---|---|---|
| Trade fee, book match or filler fill (plain or flash) | 0.02% of what each side receives, rounded up | both sides | `OrderFeeAccrued`, one per side |
| Protocol fee, pool fill | 0.01% of the input swapped | the order | `OrderFeeAccrued` |
| LP fee, pool fill | 0.02% dynamic LP fee | the order | PoolManager `Swap` |
| Dynamic fee, pool fill that backruns | half the price gap it closes | the order, in its output | `DynamicFeeCharged` |
| Priority bid | maker's choice, USDC, non-refundable | the maker | settles with fills and closes |
| MEV tax | priority fee per gas × `MEV_TAX_GAS`, in ETH | the transaction, per order creation or fill | Router `MevTaxPaid(payer, amount)` |

`calculatePoolFee` and `calculateHookFee` are zero. A maker's guarantee is its minimum output minus 0.02%.
Refunds and cancels are not charged. See [dynamic fee ordering](/protocol/dynamic-fee-ordering) for the pool-fill fee.

**MEV tax.** The Router charges `mevTax()` on `swap`, `swapWithSig`, `fillOrder` and `fillFromPoolLiquidity`,
and on every flash fill (the outer fill and each nested `fillOrderInCallback`). On a chain that orders
transactions by priority fee, searchers racing for one position bid that fee up, and the tax turns most of the
bid into protocol revenue. A transaction with no priority fee pays nothing. Plain actions pay it in `msg.value`;
flash fills pay it in flash-accounting style, see [paying the MEV tax](/protocol/flash-fills#paying-the-mev-tax).
Cancels, claims, top-ups and `matchBook` are not taxed. A searcher can still race untaxed by
repricing its own order and settling it with `matchBook`; no user loses funds that way, the protocol only
collects less (acknowledged in the 2026-11-01 Pashov review, findings 4, 5, 6 and 9).

**Invariant.** The hook's claim balance per currency equals the remaining input of open orders plus escrowed
bids, fuzzed by the matching invariant suites. The hook's own token balance is zero between transactions, so
`sweep` only moves funds sent to the hook by mistake.

## 3. Placing an order

```mermaid
sequenceDiagram
    autonumber
    participant M as Maker
    participant R as Router
    participant PM as PoolManager
    participant H as AsyncSwap hook
    participant IM as IncomingMatching

    M->>H: setExecutor(poolId, Router, true), once per pool
    M->>R: swap(order, userData) + MEV tax in msg.value
    R->>PM: unlock(Swap)
    PM->>R: unlockCallback
    R->>PM: settle MEV tax, mint it to FeeVault as native claims
    R->>PM: swap(key, exact input, hookData)
    PM->>H: beforeSwap(sender = Router)
    H->>PM: take input as hook claims
    H->>IM: stage(order): check floors, escrow bid
    Note over H,IM: A crossing arrival with no active LP liquidity<br/>is staged in transient storage, otherwise stored in the book
    H-->>PM: BeforeSwapDelta takes the whole input (custom accounting)
    R->>PM: settle input (transferFrom, ETH, or Permit2)
    opt priorityFee > 0
        R->>PM: settleFor(hook) with the USDC bid
    end
    R->>H: matchNewOrder(order)
    H->>IM: better venue first: pool or book, up to 8 pairs
    opt Remainder and active liquidity
        H->>H: guarded self-call fillOrderFromPoolLiquidity
    end
    H-->>R: matched pair count
    R-->>PM: callback returns, every delta is zero
```

Signed orders follow the same path through `swapWithSig`: one Permit2 `PermitWitnessTransferFrom` whose witness
is `OrderSignatures.hashOrder(order)`, plus an optional signed `SetExecutor` grant. An order's id is
`keccak(chainId, poolId, owner, zeroForOne, salt)`; the hook assigns the salt and emits it in `AsyncOrderCreated`.

The new order goes to the better venue first. If the pool has active liquidity and its spot price is strictly
better than the best opposing level, the pool fills up to that level and the book takes the rest. Otherwise
the book matches first and the pool must take the whole remainder or roll back. See the
[lifecycle](/protocol/order-lifecycle) for everything after placement.

## 4. Authorization

```mermaid
flowchart LR
    subgraph MakerRights["Maker (order.owner)"]
        m1["Router: swap, cancelOrder, cancelAndWithdraw,<br/>withdrawClaims, topUpPriorityFee"]
        m2["Hook: updatePrice, startAuction,<br/>setExecutor, invalidateNonce"]
        m3["Signatures: Permit2 order witness,<br/>SetExecutor, UpdatePrice, CancelOrder"]
    end
    subgraph RouterRights["Router (trusted, fixed in the hook)"]
        r1["only swap caller beforeSwap accepts"]
        r2["executeOrder, tryFillOrderFromPoolLiquidity:<br/>needs the maker's executor grant"]
        r3["flashFill: Router only, needs the grant"]
        r4["cancelOrder and topUpPriorityFee:<br/>Router only acts for order.owner"]
    end
    subgraph FlashRights["Active flash filler"]
        f1["fillOrderInCallback, matchBookInCallback:<br/>only msg.sender in the transient filler slot"]
    end
    subgraph OwnerRights["Protocol owner (two-step transfer)"]
        o1["FeeVault.collect"]
        o2["sweep: hook's raw balance only"]
        o3["no pause, no upgrade, no setter, no escrow access"]
    end
    subgraph Public["Anyone"]
        p1["open a pool"]
        p2["matchBook(key, 1..8)"]
        p3["fillFromPoolLiquidity(order)"]
        p4["fillOrder / fillOrderWithCallback (pays the maker)"]
        p5["relay a maker's signature"]
    end
```

`Router.multicall` runs several Router calls atomically as the caller. It is not payable, so native-value
actions are sent on their own. The Router can never be revoked as an executor (`CannotRevokeTrustedRouter`), so
a maker's orders are never trapped. Signed maker actions use unordered nonces in `AsyncSwap.nonceUsed`;
`invalidateNonce` revokes any of them.

## 5. Modules and libraries

Measured with solc, the hook and Router sit near the EIP-170 limit, so most logic runs in linked libraries and one
Router module. Public library functions run by DELEGATECALL in the hook's context, so escrow, books and transient
records stay in the hook.

```mermaid
flowchart TB
    subgraph RouterSide["Router side"]
        Router["Router"]
        RFF["RouterFlashFills<br/>created in the Router's constructor"]
        Router -.->|"fallback() and FlashFill unlock:<br/>DELEGATECALL, runs as the Router"| RFF
    end

    subgraph HookSide["AsyncSwap hook + linked libraries"]
        Hook["AsyncSwap"]
        IM["IncomingMatching<br/>stage · matchNewOrder · venue choice"]
        AM["AsyncMatching<br/>matchBook · fill · cancel · updatePrice<br/>fillFromPoolLiquidity"]
        MA["MultiAsset<br/>initialize (pool setup) · run (flashFill ops)"]
        DA["DutchAuction<br/>start · step"]
        PFU["PriorityFeeUpdates<br/>topUp"]
        DFO["DynamicFeeOrdering<br/>charge"]
        TP["TickPrice<br/>limit price to tick key"]
        TB["TickBitmap"]
        EP["EligiblePrice"]
        AF["AsyncFiller (internal)<br/>State, Book, fees, bids"]

        Hook -.->|linked| IM
        Hook -.->|linked| AM
        Hook -.->|linked| MA
        Hook -.->|linked| DA
        Hook -.->|linked| PFU
        IM -.->|linked| AM
        AM -.->|linked| DFO
        AM -.->|linked| TP
        AM -.->|linked| TB
        AM -.->|linked| EP
        MA -.->|linked| EP
        PFU -.->|linked| EP
        DA -.->|linked| TP
        DA -.->|linked| EP
        AM --> AF
        MA --> AF
        DA --> AF
    end

    Router -->|calls| Hook
    RFF -->|"flashFill(op), auctionPremium,<br/>asyncOrderInfo, matchBook"| Hook
```

`RouterFlashFills` called directly reaches the hook as itself, not as the Router, and `flashFill` refuses it
(`NotTrustedRouter`). Its code counts toward the Router's initcode, not its runtime.

## 6. Deployment shape

```mermaid
flowchart LR
    D["CREATE2 deployer"] -->|fixed salts, same address on every chain| Libs["TickPrice · DynamicFeeOrdering · TickBitmap<br/>EligiblePrice · PriorityFeeUpdates · MultiAsset<br/>DutchAuction · AsyncMatching · IncomingMatching"]
    Libs -.->|linked into bytecode| Hook["AsyncSwap hook<br/>mined salt for the hook flags"]
    D --> Hook
    Hook -->|constructor| Vault["FeeVault"]
    Owner["Deployer"] -->|CREATE| Router["Router(PoolManager, hook, Permit2, MEV_TAX_GAS)"]
    Router -->|constructor: new| RFF["RouterFlashFills"]
    Owner -->|CREATE| Claims["NativeClaims · TokenClaims"]
    Anyone["Anyone"] -->|PoolManager.initialize| Pool["Pool: dynamic fee, hook address"]
```

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` runs this sequence from `script/config/chains.json`.
`MEV_TAX_GAS` comes from the chain's `deployment.mevTaxGas`: 20,000,000 on Unichain, whose blocks are ordered by
priority fee, and 0 on chains ordered another way, where it would only tax ordinary tips. Measure contract
sizes with `forge build && python3 script/check-contract-sizes.py`.
