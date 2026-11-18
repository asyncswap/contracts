// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply, 18-decimal launch token. No mint, tax, pause or admin functions.
contract LaunchToken is ERC20 {
    address public immutable creator;
    /// @notice Immutable URI for public image/social metadata; clients must treat it as untrusted content.
    string public metadataURI;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply,
        address creator_,
        address recipient,
        string memory uri
    ) ERC20(name_, symbol_) {
        creator = creator_;
        metadataURI = uri;
        _mint(recipient, supply);
    }
}
