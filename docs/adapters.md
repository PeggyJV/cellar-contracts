# Adapters

Adapters integrate Cellars with external DeFi protocols, enabling them to use the assets in the protocol.

We have an established catalogue of adapters that can be used to integrate with the following protocols:

## Aave

There are adapters for both Aave V2 and V3.

The adapters support both despoting assets and borrowing assets.

Frequent uses cases include:
 - Leveraged Staking
 - Stablecoin lending
 - Leveraged Peg Arbitrage

## Aura

Adapter for Aura contracts using a specialized ERC4626 adapter.

## Balancer

Allows Cellars to interact with Stable and Boosted Stable Balancer Pools (BPs).

## Compound

Deposit and borrow assets in Compound.

## Convex

The Convex allows cellars to have positions where they are supplying, staking LPTs, and claiming rewards to Convex-Curve pools/markets.

## Curve

The Curve adapter supports creating and managing LP positions in Curve pools and depositing the LP tokens into guages to earn CRV rewards.

## Frax

The Frax adapter supports using the Frax lend protocol to deposit Frax and eary yield.

## Maker

Support for DAI staking to earn stablecoin yield.

## Morpho

## OneInch

Another source of swap liquidity.


## 0x

Another source of swap liquidity.

## Pendle

Enables the cellar to mint SY tokes and minting PT and YT tokens from the SY tokens.

The positions are these tokens and the adapter doesn't expose a position.

## Uniswap

The adapter supports swaps against both Uniswap V2 and V3. It supports holding multiple NFT LP positions in Uniswap V3.


## Staking Adapters

There is a universal template adapter that can specialied into staking assets into various protocols. We have support for the major LRT and LST protocols.
