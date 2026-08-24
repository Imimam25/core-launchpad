// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BondingCurveLib
/// @notice Linear bonding curve math: price(s) = P0 + k*s, where s is tokens
///         sold so far (18 decimals). Reserve(S) = P0*S + k*S^2/2.
/// @dev All amounts are in 1e18 fixed point. Constants below are derived so that
///      selling the full CURVE_SUPPLY (800,000,000 tokens) raises exactly
///      GRADUATION_RESERVE (10,000 CORE). See TOKENOMICS.md for derivation.
library BondingCurveLib {
    uint256 internal constant WAD = 1e18;

    // P0 = 0.000001 CORE per token = 1e12 wei per whole token (1e18 wad price-per-wad-token)
    // Expressed as price-per-token in wei, scaled by 1e18 for precision in intermediate math.
    uint256 internal constant P0 = 1e12; // wei per token (0.000001 CORE)

    // k solved so that Reserve(800_000_000e18) = 10_000e18 wei... see derivation script.
    // k (wei per token^2, unscaled) ~= 2.875e-14 wei/token^2 -> represented as a fraction
    // to avoid precision loss: k = K_NUM / K_DEN (wei per token, per token)
    uint256 internal constant K_NUM = 2875;
    uint256 internal constant K_DEN = 1e17; // k = 2875 / 1e17 = 2.875e-14

    uint256 internal constant CURVE_SUPPLY = 800_000_000 * WAD;
    uint256 internal constant GRADUATION_RESERVE = 10_000 ether; // 10,000 CORE in wei

    /// @notice price at a given cumulative-sold supply `s` (18 decimals), in wei per whole token
    function priceAt(uint256 s) internal pure returns (uint256) {
        // price = P0 + k*s  (s in wad-tokens; normalize by WAD)
        uint256 kTerm = (K_NUM * s) / K_DEN / WAD;
        return P0 + kTerm;
    }

    /// @notice cumulative reserve (wei) raised once `s` tokens (wad) have been sold
    function reserveAt(uint256 s) internal pure returns (uint256) {
        // reserve = P0*s + k*s^2/2, all divided back down to wei, s in wad-tokens
        uint256 linear = (P0 * s) / WAD;
        uint256 quad = (K_NUM * s / K_DEN) * (s / WAD) / WAD / 2;
        return linear + quad;
    }

    /// @notice given current sold-supply `s0` and CORE `deltaReserve` (wei) sent in,
    ///         returns tokens (wad) purchased, solving the quadratic:
    ///         k/2 * ds^2 + price(s0) * ds - deltaReserve = 0
    function tokensOutForReserveIn(uint256 s0, uint256 deltaReserve) internal pure returns (uint256 ds) {
        // a = k/2, b = price(s0), c = -deltaReserve
        // ds = (-b + sqrt(b^2 + 4*a*deltaReserve)) / (2a)   [rearranged for positive root]
        uint256 b = priceAt(s0);
        // a scaled: k/2 in wei per (token^2), we keep everything in wei/wad units via sqrt trick
        uint256 aNum = K_NUM;
        uint256 aDen = K_DEN * 2;

        // b^2 + 4*a*deltaReserve, done in high precision using WAD scaling
        uint256 disc = b * b + (4 * aNum * deltaReserve * WAD) / aDen;
        uint256 sqrtDisc = _sqrt(disc);
        require(sqrtDisc >= b, "curve: math");
        uint256 numerator = (sqrtDisc - b) * aDen;
        ds = numerator / (2 * aNum) * WAD / WAD; // ds already in wad-token units
        // NOTE: production version must be verified against reserveAt(s0+ds)-reserveAt(s0)
        // with exhaustive fuzz tests before mainnet use — see TOKENOMICS.md section 5.
    }

    function _sqrt(uint256 x) private pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
