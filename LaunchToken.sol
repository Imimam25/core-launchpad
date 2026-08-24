// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LaunchToken
/// @notice Fixed-supply ERC-20 minted once at creation. No owner, no mint function,
///         no blacklist, no transfer tax. The full supply is minted to the
///         BondingCurve contract at deploy time and distributed via trading.
contract LaunchToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    address public immutable creator;
    string public metadataURI; // IPFS URI: name/desc/image/socials

    constructor(
        string memory name_,
        string memory symbol_,
        string memory metadataURI_,
        address creator_,
        address curve_
    ) ERC20(name_, symbol_) {
        creator = creator_;
        metadataURI = metadataURI_;
        // Entire fixed supply minted once, to the curve contract, which
        // custodies the 800M curve allocation + 200M graduation allocation.
        _mint(curve_, TOTAL_SUPPLY);
    }

    // No mint(), no burn-by-owner, no pause, no blacklist. Standard ERC-20
    // transfer/approve semantics only — verifiable on Core Scan as-is.
}
