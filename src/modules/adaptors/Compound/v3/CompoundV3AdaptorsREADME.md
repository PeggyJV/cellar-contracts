# CompoundV3Adaptor Development README

This file documents where this adaptor development and branch (feat/Compound-v3-Supply-Adaptor) was left off. Recall:

- CompoundV3 Adaptors (`CompoundV3CollateralAdaptor`, `CompoundV3DebtAdaptor`, `CompoundVe3ExtraLogic`, `CompoundV3SupplyAdaptor`) all drafted up (implementation code written)
- Unit tests for `CompoundV3SupplyAdaptor` written
- Decided to hold off further development of unit tests for these adaptors && external auditing of them until there are Strategists that need them for good reason.

## Main Hurdles to Deem CompoundV3 Integration Worthwhile

1. APY needs to be good enough compared to other opportunities
2. CompoundV3 carries out full liquidiation on positions. This is considered too high of a risk vector since vaults would likely carry highly-leveraged positions. The APY mentioned in #1 would need to be very attractive to warrant the risk.
3. For implementing an extra factor of safety on a borrow position for a vault: Is there a getter to obtain the delta of the collateral normalized to the baseAsset for a lending market? Right now the logic looks like one can get the bool if liquidity > 0, but not the delta that causes the liquidity to be > 0.
4. What happens if a supply position wants to withdraw but all of the baseAsset in the lending market is being lent out?

For Remaining TODOs for the project, see the PR message.
