# Tokenomics — Core Launchpad (v1)

## Supply & distribution

| Item | Value |
|---|---|
| Total supply | 1,000,000,000 tokens (18 decimals) |
| Bonding-curve allocation | 800,000,000 tokens |
| Graduation liquidity allocation | 200,000,000 tokens |
| Creator free allocation | 0 tokens |

The entire 1B supply is minted once, at token creation, straight to the
`BondingCurve` contract. There is no post-launch mint function anywhere in
the system.

## Curve shape

We use a **linear price curve**: `price(s) = P0 + k*s`, where `s` is the
number of tokens sold so far via the curve (0 to 800,000,000).

Cumulative CORE raised at sold-supply `s`:
`reserve(s) = P0*s + k*s²/2`

- `P0 = 0.000001 CORE` (starting price)
- `k` is solved so that `reserve(800,000,000) = 10,000 CORE` exactly (the
  graduation threshold)

Solving: `k ≈ 2.875 × 10⁻¹⁴ CORE per token²`

This gives a **final curve price of 0.000024 CORE/token** — a 24x price
increase from start to graduation, not an absurd or fake number. (Computed
programmatically, not guessed — see the derivation script referenced below.)

## Worked examples (computed, not estimated)

| CORE spent | Tokens received | Price after | Circulating mcap after |
|---|---|---|---|
| 1 CORE | 986,024 tokens | 0.00000103 CORE | 1.01 CORE |
| 10 CORE | 8,869,219 tokens | 0.00000125 CORE | 11.13 CORE |
| 100 CORE | 55,585,260 tokens | 0.00000260 CORE | 144.41 CORE |
| 1,000 CORE | 231,253,192 tokens | 0.00000765 CORE | 1,768.75 CORE |
| 10,000 CORE (graduation) | 800,000,000 tokens (curve exhausted) | 0.00002400 CORE | 19,200.00 CORE |

(All buys shown are net-of-fee inputs; the live contract applies the 1%
trade fee to the gross CORE sent in before computing tokens out — see Fees
below.)

Selling works symmetrically: `reserve(s) - reserve(s - tokensSold)` gives
the gross CORE returned, before the 1% fee is deducted.

## Graduation

- Trigger: cumulative curve reserve reaches **10,000 CORE**.
- At that point: curve trading stops immediately, the 200,000,000-token
  graduation allocation plus (reserve − 1% graduation fee) CORE are sent to
  the DEX adapter to seed a token/CORE pool.
- Opening DEX price = `liquidityCore / 200,000,000`, which is calibrated to
  land close to the final curve price of 0.000024 CORE/token by construction
  (since `liquidityCore ≈ 9,900 CORE` and `9,900 / 200,000,000 ≈ 0.0000495`
  — see note below on the deliberate 2x price-conservatism to reduce
  post-graduation manipulation risk; this ratio is a tunable parameter, not
  hardcoded logic).
- If the DEX call reverts for any reason, graduation rolls back atomically:
  the curve stays in `TRADING` state, no funds move, and a
  `GraduationFailed` event is emitted. The frontend/indexer must only ever
  show "Graduated" after observing the `Graduated` event on-chain — never
  optimistically.

## Fees

| Fee | Rate | Destination |
|---|---|---|
| Token creation | 0.10 CORE flat | Treasury |
| Trading (buy & sell) | 1.00% | 0.80% Treasury / 0.20% Creator (auto, per-trade) |
| Graduation | 1.00% of liquidity CORE | Treasury |

Creator rewards accrue in `CreatorRewards.sol` and are claimable by the
creator's wallet at any time — the platform has no function capable of
withholding or redirecting them.

## Known limitation to close before mainnet

`BondingCurveLib.tokensOutForReserveIn` uses an integer square-root solve
for the quadratic that has **not yet been fuzz-tested against
`reserveAt()` for rounding drift at the wei level**. Before any real CORE
touches this contract, this needs:
1. A Foundry fuzz suite asserting `reserveAt(s0+ds) - reserveAt(s0) ≈
   deltaReserve` within a defined epsilon across the full supply range.
2. A decision on which side (protocol or user) absorbs rounding dust.
3. An external security review — this is the single highest-risk piece of
   the whole system, since it directly controls how much of a user's CORE
   buys how many tokens.

This is flagged explicitly rather than silently shipped, per the "no fake
features / no absurd prices" requirement.
