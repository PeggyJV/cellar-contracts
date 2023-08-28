# **Details for Extra Functionality with Aura Protocol (`AuraExtrasAdaptor.sol`)**

## Miscellaneous AURA Adaptor Scope

AURA protocol has various extra features outside of the basic functions of depositing and withdrawing BPTs into the protocol. Those of interest include:

1. `getRewards()` - a function call within each AURA rewards pool that allows a user to claim rewards (incl. "extra rewards") from their respective positions in the pool.
2. `lockAuraBal()` - functionality includes locking auraBAL into the AURA protocol for a cellar.
3. `stakeAURA()` - Functionality includes staking AURA protocol for a cellar. This could be of particular interest if Sommelier has share tokens in Balancer pools and can create interesting economic flywheels with $BAL emissions and Aura protocol rewards.

This issue includes scoping out how best to address this in an effective manner. The current idea is to create a`AuraExtrasAdaptor.sol`. The details of the design is as follows.

---
**`getRewards()`**

Params:

- @param \_auraPool (or maybe \_pid) that cellar is part of and is claiming rewards from
- @param \_extraRewards bool specifying whether or not to claim "extraRewards"
  NOTE: I'm not sure when we wouldn't want to claim extraRewards (perhaps there are tokens are that get hacked or something)

Each Aura pool has a `BaseRewardPool` that encompasses functionality with a `BaseRewardToken` and `extraRewards`.

- `BaseRewardToken` is typically $AURA I believe
- `extraRewards` corresponds to other ERC20 incentive rewards.

Function sig of `getReward()` in `BaseRewardPool` is:
`function getReward(address _account, bool _claimExtras) public updateReward(_account) returns(bool)`

where:
_ @param \_account Account for which to claim
_ @param \_claimExtras Get the child rewards too? \* @return whether or not the tx was successful

### Miscellaneous Notes:

- Rewards seem to be "stashed" but need to explore that more when withdraw() is called within the Aura pool. The highlight is that rewards are not rolled into more BPT, and the amount of BPT out to the user is the amount requested. So it seems rewards are separate to the asset being staked into the ERC4626 here. So how do we keep track of rewards that each user should get for their share in the vault?
- Not sure if we should have a whitelist for the rewards contracts that are deemed acceptable --> I guess that's on AURA to decide, so we need to keep an eye on what AURA is accepting as extra rewards then.
  - They could introduce a malicious rewards token and contract and apply it to users. TODO: assess viability with this attack though.

---

**`lockAuraBal()`**

Initially the idea was to create custom strategist functions to deposit `auraBal` to the `auraBal Compounder`. Upon initial (rough) review, the auraBal Compounder adheres to the IERC4626 standard. Thus a possible route for integration with the AuraBal Compounder is to treat it as a trusted CellarAdaptor position within the Sommelier architecture.

Ex.) Say we have a cellar that has auraBAL as its base asset. The cellar would add a cellarAdaptor position and trust the AuraBal Compounder Vault contract. Appropriate pricing resources would be trusted and put in place for the Sommelier pricing setup. Afterwards the Cellar now simply directs AuraBal to the AuraBal Compounder. Simple.

TODO:

- [ ] Review the extra functions within AuraBal Compounder Vault.
- [ ] Review with Strategist teams and internal smart contract team.

---

**`stakeAURA()`**

From checking on etherscan, the aura vote proxy was found. This set of contracts is used to lock AURA into the protocol for users and provide extra yield and the ability to vote and possibly influence the Balancer ecosystem using Aura's veBAL.

_This functionality is likely not a high priority considering the development effort required and the long-time-frame to establish a large locked AURA position._

When it is picked up, see references (Aura Vote Proxy) for details on the VoteProxy, and further details within the docs (and possibly within the curve docs).

---
## References

1. Aura Pool Example: https://etherscan.deth.net/address/0x032B676d5D55e8ECbAe88ebEE0AA10fB5f72F6CB
2. AuraBalVault (AKA AuraBal Compounder Vault): https://etherscan.io/address/0xfAA2eD111B4F580fCb85C48E6DC6782Dc5FCD7a6#code
   && AuraBal OFT? https://etherscan.io/address/0xdF9080B6BfE4630a97A0655C0016E0e9B43a7C68#readContract
3. Aura Vote Proxy https://etherscan.deth.net/address/0xaF52695E1bB01A16D33D7194C28C42b10e0Dbec2
