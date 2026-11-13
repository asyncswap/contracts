# TickBitmap

[Git Source](https://github.com/asyncswap/contracts/blob/6aa19f681f6dcda07dbe32d621088bdd4be8da99/src/libraries/TickBitmap.sol)

Three-level occupancy bitmap for the bounded tick-key domain.

<i>
  Not a replacement for the 128-bit fee/sequence tree. Changes storage layout.
</i>

## Constants

### MAX_KEY

```solidity
uint128 internal constant MAX_KEY = 1_774_545;
```

## Functions

<a id="insert-tree-uint128" />

### insert

```solidity
function insert(Tree storage self, uint128 key) internal returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| key | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="remove-tree-uint128" />

### remove

```solidity
function remove(Tree storage self, uint128 key) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| key | `uint128` |  |

<a id="best-tree-bool" />

### best

```solidity
function best(Tree storage self, bool highest) public view returns (bool, uint128);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| highest | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |
| \<none> | `uint128` |  |

<a id="_bit-uint256-bool" />

### \_bit

```solidity
function _bit(uint256 bits, bool highest) private pure returns (uint8);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| bits | `uint256` |  |
| highest | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint8` |  |

## Errors

### InvalidKey

```solidity
error InvalidKey();
```

### PriceLevelMissing

```solidity
error PriceLevelMissing();
```

## Structs

### Tree

```solidity
struct Tree {
        // Each parent bit means its child word is nonempty: root -> middle -> leaf.
        uint256 root;
        mapping(uint256 group => uint256 bits) middle;
        mapping(uint256 word => uint256 bits) leaves;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| root | `uint256` |  |
| middle | `mapping(uint256 group => uint256 bits)` |  |
| leaves | `mapping(uint256 word => uint256 bits)` |  |
