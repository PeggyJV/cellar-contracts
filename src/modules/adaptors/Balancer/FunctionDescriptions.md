# Plain English Function Descriptions

This document provides high level details on how the "universal adaptor" code would work with others yield aggregator code, and "Plain English Function Descriptions."

It serves as a quick reference point versus digging into the interface file, `IBalancerStablePoolAdaptor.sol`, and/or the example implementation file `BalancerStablePoolAdaptor.sol`. Feel free to skip to those files and see their nat spec accordingly.

Please read the `README.md` within this sub-directory for context of the work associated to this document.

---

## Function Breakdown

This PR is starting with the idea of a "Universal Adaptor" for integrating into the Balancer protocol. Currently the idea is to:

- Have different interfaces and base implementation smart contracts to integrate into the respective Balancer Pool Type. There are various pool types in Balancer.
- Focus on integration into a Stable Pool type.

Thus, the `IBalancerStablePoolAdaptor.sol` functions will be broken down below.

### `joinPool()`

Basic Function Description: Allows strategists to join Balancer pools using EXACT_TOKENS_IN_FOR_BPT_OUT joins.

Function signature:

```
    function joinPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsBeforeJoin,
        SwapData memory swapData,
        uint256 minimumBpt
    ) external
```

Input Parameter Descriptions

- @param `targetBpt` The specified Balancer Pool ERC20 to join
- @param `swapsBeforeJoin` Data for a single swap executed by `swap` as specified by struct SingleSwap (see IVault.sol)
- @param `swapData` Information pertaining to aspects including minAmountsForSwaps, and swapDeadlines
- @param `minimumBpt` Minimum amount of BPT to be included in request encoded data.
  NOTE: Max Available logic IS supported.

Extra Notes:

- `swapsBeforeJoin` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
  - IE if the first token in expected token array is DAI, the first swap in `swapsBeforeJoin` MUST be for DAI.
- Implementation logic to likely include pricing mechanic that checks for slippage and is often custom to the respective yield protocol or project.

---

### `exitPool()`

Basic Function Description: Allows strategists to exit Balancer pools using any exit.

Function signature:

```
    function exitPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsAfterExit,
        SwapData memory swapData,
        IVault.ExitPoolRequest memory request
    ) external;
```

Input Parameter Descriptions

- @param `targetBpt` The specified Balancer Pool to exit
- @param `swapsAfterExit` Data for a single swap executed by `swap` as specified by struct SingleSwap
- @param `swapData` Information pertaining to aspects including minAmountsForSwaps, and swapDeadlines
- @param `request` ExitPoolRequest Struct containing assets involved, minAmountsOut, userData, and whether internalBalances are used (see IVault.sol)
- NOTE: Max Available logic IS NOT supported.

Extra Notes:

- The amounts in `swapsAfterExit` are overwritten by the actual amount out received from the swap.
- `swapsAfterExit` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
-      IE if the first token in expected token array is BB A DAI, the first swap in `swapsBeforeJoin` MUST be to
-      swap BB A DAI.
- Implementation logic to likely include pricing mechanic that checks for slippage and is often custom to the respective yield protocol or project.

---

### `stakeBPT()`

Basic Function Description: Stake (deposit) BPTs into respective pool gauge.

Function signature:

```
    function stakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountIn) external;
```

Input Parameter Descriptions

- @param \_bpt address of BPTs to stake
- @param \_liquidityGauge Balancer gauge to deposit (stake) BPTs into.
- @param \_amountIn number of BPTs to stake.

Extra Notes:

- Interface ILiquidityGaugev3Custom.sol is custom as Balancer/Curve do not provide for liquidityGauges.
- This function will likely validate that the `_bpt` and `_liquidityGauge` are trusted and in use with the respective yield protocol/project. Revocation of approvals needed too at end of transaction to protect respective ERC4626 vault.

---

### `unstakeBPT()`

Basic Function Description: Unstake (withdraw) BPT from respective pool gauge.

Function signature:

```
    function unstakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountOut) external;
```

Input Parameter Descriptions

- @param \_bpt address of BPTs to unstake.
- @param \_liquidityGauge Balancer gauge to withdraw (unstake) BPTs into.
- @param \_amountOut number of BPTs to unstake

Extra Notes:

- Interface ILiquidityGaugev3Custom.sol is custom as Balancer/Curve do not provide for liquidityGauges.
- This function will likely validate that the `_bpt` and `_liquidityGauge` are trusted and in use with the respective yield protocol/project. Revocation of approvals needed too at end of transaction to protect respective ERC4626 vault.

---

### `claimRewards()`

Basic Function Description: Claim rewards ($BAL) from LP position.

Function signature:

```
    function claimRewards(address gauge) external;
```

Input Parameter Descriptions

- @param gauge Balancer gauge to claim rewards from.

Extra Notes:

- Rewards are only accrued for staked positions

---

### `makeFlashLoan()`

Basic Function Description: Start a flash loan using Balancer.

Function signature:

```
    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory data) external;
```

Input Parameter Descriptions

- @param tokens specified IERC20 tokens to loan
- @param amounts number of respective ERC20s to flash loan
- @param data TODO: check w/ Crispy what this data is --> see https://etherscan.deth.net/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8
