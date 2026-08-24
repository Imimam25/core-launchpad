// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDexAdapter
/// @notice Abstraction over "whichever Core Mainnet DEX we graduate into."
///         Swapping DEXs later means deploying a new adapter that implements
///         this interface and pointing LaunchpadFactory at it — no changes
///         to BondingCurve or LaunchToken required.
interface IDexAdapter {
    /// @notice Creates (or fetches) the token/CORE pool and adds initial liquidity.
    /// @param token The graduated token address
    /// @param tokenAmount Amount of token to seed liquidity with (wad)
    /// @return pool The resulting LP pool/pair address
    /// @return lpAmount The amount of LP tokens minted to this adapter
    function createPoolAndAddLiquidity(address token, uint256 tokenAmount)
        external
        payable
        returns (address pool, uint256 lpAmount);

    /// @notice Returns the pool address for a token, or address(0) if none exists yet.
    function getPool(address token) external view returns (address pool);

    /// @notice Read-only quote for how much CORE a given token amount would fetch,
    ///         used by the frontend post-graduation before the DEX UI takes over.
    function getQuote(address token, uint256 tokenAmountIn) external view returns (uint256 coreOut);
}

/*
  IMPORTANT — DO NOT WIRE THIS TO A REAL ROUTER/FACTORY ADDRESS YET.

  Before implementing IceCreamSwapAdapter.sol (or any other adapter), the
  router/factory addresses must be pulled from that DEX's *current* official
  docs and verified on Core Scan (verified source, checked against the
  project's official announcement channel) — not invented or guessed here.
  This is flagged as an explicit manual verification step in DEPLOYMENT.md
  for phase 2, precisely because a wrong address here would let graduation
  silently send real user liquidity to a broken or malicious contract.
*/
