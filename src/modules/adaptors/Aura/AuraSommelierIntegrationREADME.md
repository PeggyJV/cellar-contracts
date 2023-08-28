# 🍷🐸🟣 Sommelier-AURA-Integration Details | _(AKA Purple-Frogs-at-the-Vineyard Integration Details)_

**_NOTE: this is a wip integration. None of this code or concepts are to be used, and are not finalized (thus the TODOs scattered through the markdown right now)._**

# **Integration Details**

This README outlines how the basic functionality of the Sommelier and Aura protocol integration will work.

1. Sommelier Cellars will carry out basic functionality with Aura protocol via the use of a `CellarAdaptor position` where each Aura pool has a `BaseRewardPool4626.sol` that adheres to the IERC4626 standard.

2. Custom adaptors or Cellar Adaptor Positions, etc. are used to integrate with auraBalVaults && lockAura smart contracts for staking auraBAL, and locking AURA and participating in AURA's voting schema, respectively.

## **Basic Functionality Details**

Part of the due diligence for any integration involves understanding the transaction details cellars conduct, including into the underlying new protocol in question.

Since basic functions into Aura protocol are carried out using a `CellarAdaptor` position, this document will outline what is happening within the Aura smart contracts.

---

# Setup / Example Walk-Through

Say there is a cellar that accepts BPTs, call it bptCellar. bptCellar adds a `CellarAdaptor` position that specifies an AURA `BaseRewardPool4626` address that matches the accepted BPT `asset`.

## **Base Functions**

### **`deposit()`**

Let's assume that the CellarAdaptorPosition is the holding position. The BPTs would be deposited into the Sommelier Cellar, and directly be deposited into the Aura contract from the cellar. This is done in the following steps:

1. `deposit()` hooks activated and `assets` sent from Cellar to Aura using `deposit()` within the AURA contract. Within this function there are a couple of takeaways:

- `operator` is the `Booster.sol` contract (copied from Convex) that is associated to this pool. This contract mints `aura-BPT` to the cellar.
- `_processStake()` is called immediately, where the `BPTs` from the cellar are staked within Balancer to earn Aura protocol rewards (that are distributed to participants and the protocol itself).
- Steps included:
  - safeTransfers BPT to aura pool
  - Uses `booster` (called `operator` in this function) to get aura-BPT (copied code from Convex)
    - TODO: diff check on this
  - Checks that 1:1 for auraBPT:BPT is obtained, or more auraBPT. This is bc it is a 1:1 relationship, unless there are lots of reward auraBPT in the pool, then you get more auraBPT per BPT I think.
    - otherwise reverts
  - Stakes aura-BPT, via `IRewards.sol` on `extraRewards` array of addresses. I believe this is from Synthetix (convex used it too). Implicitly it looks like `stake()` actually stakes the `underlyingBPT` into the respective `BalancerGauge`.
    - Here user gets `aura-BPT-vault` token which represent staked underlying BPT into aura protocol I think. OR they get `staked-aura-BPT`. TODO: confirm this

### **`withdraw()`**

User wants to exit their position within the cellar and get BPTs back. These aura positions can be staked aura-BPTs. So they would need to be unwound from this position, at worst.

1. `withdraw()` hooks activated and `assets` are withdrawn from AURA using `withdraw()` within the AURA contract. Within this function there are a couple of takeaways:

`_withdrawAndUnwrapTo()` is the helper called from `BaseRewardPoolERC4626` `withdraw()` function. It is a helper in `BaseRewardPool.sol`.

- extraRewards contracts are withdrawn from
- internal accounting adjusted: totalSupply, balances[from]
- `booster` contract called to `withdraw()` BPTs directly to user
  - TODO: look over this more, but ultimately `_withdraw()` is called in `booster` and it calls `IStaker(address staker)` which I believe unstakes any BPTs staked in the `staker` address which I think is the BPT gauge.
- Then it claims any rewards in any related `stash` contracts
- Then it transfers the BPTs out to the user.

### **`balanceOf()`**

- Calls `previewRedeem()` on `BaseRewardPoolERC4626` for Aura pool.
- Calls `previewWithdraw()` " which calls `convertToShares(assets)`.
- Finally just returning `assets` as the Aura Pool Shares are 1:1 with BPTs received.
- This means that accounting of any rewards accumulated (obtained from calling `getReward()` on the pool, which I believe calls it on any stashes), is done with erc20Adaptor positions for reward tokens.
  - TODO: confirm the above

> Recall for rewards with cellars: When it comes to the UX/backend for a user exiting the cellar, it’ll look at credit and debt positions (let’s just say), and then it’ll go through them in order. So if a user wanted to exit a 1 million BPT position from a cellar with AURA positions, and there were rewards accumulated from their initial 1m BPT over time, they wouldn’t necessarily get the rewards (let’s say AURA).

> It all depends on how the strategist has the Cellar setup. The strategist decides on how they handle rewards (auto-compound to baseAsset, etc.), including the order of which the positions are in for exiting and what the user gets back when exiting. All in all it comes out to a normalized price of assets the user wants back from the cellar (normalized to USD and the base asset), but the tokens out aren’t necessarily the base asset.

## **Strategist Functions**

**`depositToCellar()`**

- Same as deposit flow described before.

**`withdrawFromCellar()`**

- Same as withdraw flow descirbed before.
