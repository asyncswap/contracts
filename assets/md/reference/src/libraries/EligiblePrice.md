# EligiblePrice

[Git Source](https://github.com/asyncswap/contracts/blob/16b469f37d1b441e4bdde50c26d9dc0c32b018c1/src/libraries/EligiblePrice.sol)

Exact-price summaries on a priority-key radix tree.

<i>
  A buy subtree stores its maximum limit; a sell subtree its minimum.
  This is an existence certificate, not an approximation of an order's limit.
</i>

## Functions

<a id="le-ratio-ratio" />

### le

<i>
  Exact comparison of positive-denominator ratios using two 512-bit products.
</i>

```solidity
function le(Ratio memory a, Ratio memory b) internal pure returns (bool result);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| a | `Ratio` |  |
| b | `Ratio` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| result | `bool` |  |

<a id="refresh-radixpricetree-tree-mapping-uint32-ratio-uint128-ratio-bool" />

### refresh

```solidity
function refresh(
        RadixPriceTree.Tree storage tree,
        mapping(uint32 => Ratio) storage bounds,
        uint128 rank,
        Ratio memory price,
        bool isBuy
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tree | `RadixPriceTree.Tree` |  |
| bounds | `mapping(uint32 => Ratio)` |  |
| rank | `uint128` |  |
| price | `Ratio` |  |
| isBuy | `bool` |  |

<a id="remove-radixpricetree-tree-mapping-uint32-ratio-uint128-bool" />

### remove

```solidity
function remove(RadixPriceTree.Tree storage tree, mapping(uint32 => Ratio) storage bounds, uint128 rank, bool isBuy)
        internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tree | `RadixPriceTree.Tree` |  |
| bounds | `mapping(uint32 => Ratio)` |  |
| rank | `uint128` |  |
| isBuy | `bool` |  |

<a id="_repair-radixpricetree-tree-mapping-uint32-ratio-uint32-bool-bool" />

### \_repair

```solidity
function _repair(
        RadixPriceTree.Tree storage tree,
        mapping(uint32 => Ratio) storage bounds,
        uint32 cursor,
        bool isBuy,
        bool forceFirst
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tree | `RadixPriceTree.Tree` |  |
| bounds | `mapping(uint32 => Ratio)` |  |
| cursor | `uint32` |  |
| isBuy | `bool` |  |
| forceFirst | `bool` |  |

<a id="_eligible-ratio-ratio-bool" />

### \_eligible

```solidity
function _eligible(Ratio memory bound, Ratio memory limit, bool isBuy) private pure returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| bound | `Ratio` |  |
| limit | `Ratio` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="best-radixpricetree-tree-mapping-uint32-ratio-ratio-bool" />

### best

Highest priority key among orders crossing `limit`, in at most 128 branches.

<i>
  Right children have greater priority keys. No backtracking or linear scan.
</i>

```solidity
function best(
        RadixPriceTree.Tree storage tree,
        mapping(uint32 => Ratio) storage bounds,
        Ratio memory limit,
        bool isBuy
    ) internal view returns (bool found, uint128 rank);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tree | `RadixPriceTree.Tree` |  |
| bounds | `mapping(uint32 => Ratio)` |  |
| limit | `Ratio` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| rank | `uint128` |  |

## Structs

### Ratio

```solidity
struct Ratio {
        uint256 numerator;
        uint256 denominator;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| numerator | `uint256` |  |
| denominator | `uint256` |  |
