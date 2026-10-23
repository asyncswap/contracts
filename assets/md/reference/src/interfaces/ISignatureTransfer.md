# ISignatureTransfer

[Git Source](https://github.com/asyncswap/contracts/blob/961879f26c96b50496eca8bbfc58db86aacc2b9f/src/interfaces/ISignatureTransfer.sol)

**Title:** ISignatureTransfer

Minimal subset of Uniswap Permit2's SignatureTransfer interface used by the Router.
Canonical Permit2 lives at 0x000000000022D473030F116dDEE9F6B43aC78BA3 on every chain.

<i>
  Vendored instead of imported because Permit2's sources pin solc 0.8.17.
</i>

## Functions

<a id="permitwitnesstransferfrom-permittransferfrom-signaturetransferdetails-address-bytes32-string-bytes" />

### permitWitnessTransferFrom

```solidity
function permitWitnessTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| permit | `PermitTransferFrom` |  |
| transferDetails | `SignatureTransferDetails` |  |
| owner | `address` |  |
| witness | `bytes32` |  |
| witnessTypeString | `string` |  |
| signature | `bytes` |  |

## Structs

### TokenPermissions

```solidity
struct TokenPermissions {
        address token;
        uint256 amount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| amount | `uint256` |  |

### PermitTransferFrom

```solidity
struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| permitted | `TokenPermissions` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |

### SignatureTransferDetails

```solidity
struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| to | `address` |  |
| requestedAmount | `uint256` |  |
