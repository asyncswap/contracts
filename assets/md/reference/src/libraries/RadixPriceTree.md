# RadixPriceTree

[Git Source](https://github.com/asyncswap/contracts/blob/19bb8dcdd03f03343b1b3af3ad1415292420077b/src/libraries/RadixPriceTree.sol)

Patricia radix index for uint128 price levels. Inserts and removals
traverse at most 128 branch bits; each distinct price creates one
leaf and at most one branch node. Node ids released by `remove` are
recycled by later inserts, so the id counter only grows with the peak
number of simultaneously stored prices and can never be exhausted in
practice (2^31 simultaneous levels).

## Functions

<a id="insert-tree-uint128" />

### insert

```solidity
function insert(Tree storage self, uint128 price) internal returns (bool created);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| created | `bool` |  |

<a id="remove-tree-uint128" />

### remove

```solidity
function remove(Tree storage self, uint128 price) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| price | `uint128` |  |

<a id="best-tree-bool" />

### best

```solidity
function best(Tree storage self, bool highest) internal view returns (bool found, uint128 price);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| highest | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| price | `uint128` |  |

<a id="_newnode-tree" />

### \_newNode

<i>
  Reuse a released id first; only grow the counter when none is free. A freed id
  is referenced by nothing (its parent, sibling and `leaves` entries were rewired in
  `remove`), so reusing it cannot alias a live node.
</i>

```solidity
function _newNode(Tree storage self) private returns (uint32 id);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `uint32` |  |

<a id="_freenode-tree-uint32" />

### \_freeNode

```solidity
function _freeNode(Tree storage self, uint32 id) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `Tree` |  |
| id | `uint32` |  |

<a id="_bitset-uint128-uint8" />

### \_bitSet

```solidity
function _bitSet(uint128 value, uint8 bit) private pure returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| value | `uint128` |  |
| bit | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="_mostsignificantbit-uint128" />

### \_mostSignificantBit

```solidity
function _mostSignificantBit(uint128 value) private pure returns (uint8 bit);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| value | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| bit | `uint8` |  |

## Errors

### PriceLevelMissing

```solidity
error PriceLevelMissing();
```

### NodeIdOverflow

```solidity
error NodeIdOverflow();
```

## Structs

### Node

```solidity
struct Node {
        uint32 parent;
        uint32 left;
        uint32 right;
        uint128 price;
        uint8 bit;
        bool leaf;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| parent | `uint32` |  |
| left | `uint32` |  |
| right | `uint32` |  |
| price | `uint128` |  |
| bit | `uint8` |  |
| leaf | `bool` |  |

### Tree

```solidity
struct Tree {
        uint32 root;
        uint32 nextNodeId;
        /// @dev Ids released by `remove`; `_newNode` pops from here before growing `nextNodeId`.
        uint32[] freeIds;
        mapping(uint32 id => Node) nodes;
        mapping(uint128 price => uint32 id) leaves;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| root | `uint32` |  |
| nextNodeId | `uint32` |  |
| freeIds | `uint32[]` |  |
| nodes | `mapping(uint32 id => Node)` |  |
| leaves | `mapping(uint128 price => uint32 id)` |  |
