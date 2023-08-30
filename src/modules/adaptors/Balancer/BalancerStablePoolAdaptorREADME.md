# 🍷🏊🏻‍♀️ Balancer Universal Adaptor Project Details | _(AKA Join-The-Pool-The-Water's-Warm Project Details)_

> **NOTE: THE PURPOSE OF THIS REPO IS TO FACILITATE DISCUSSION AROUND A UNIVERSAL BALANCER POOL ADAPTOR. THIS REPO FOCUSES ON USING A STABLEPOOL ADAPTOR AS THE FIRST EXAMPLE AS OTHER ADAPTORS CAN BE CREATED FOR DIFFERENT POOL TYPES.**

> _Also, this is a wip integration. None of this code or concepts are to be used, and are not finalized (thus the TODOs scattered through the markdown right now)._

# **General Info and Disclaimer**

This repo serves as a home for open-source ERC 4626 Adaptor work pertaining to specific protocols. These are not audited, so use them at your own risk.

The aim is to have numerous protocol integration contracts documented and to lower the barrier to entry for projects using ERC 4626 Vaults from integrating with said protocols.

Ultimately, there is A LOT to creating a yield aggregator or any other protocol that uses ERC 4626 standards in DeFi, but this repo serves as a public good to help lessen that workload.

# **Integration Details**

This repo is starting with the idea of a "Universal Adaptor" for integrating into the Balancer protocol. Currently the idea is to have different interfaces and base implementation smart contracts to integrate into the respective Balancer Pool Type. There are various pool types in Balancer.

Yield Aggregator projects have historically integrated with yield strategies and DeFi instruments revolving around stablecoin assets. Therefore the first pool type of focus will be the stable pool.

The associated files for the Stable Pool Balancer Adaptor Integration include:

1. `IBalancerStablePoolAdaptor.sol`: a generic interface for StablePool integration
2. `BalancerStablePoolAdaptor.sol`: an implementation example that has `internal virtual` helper functions that can be overridden so different projects can implement their own specific implementation code while still adhering / saving time with this pre-existing code via inheritance.

# **TODOs:**

- [ ] Create standalone repo with: `IBalancerStablePoolAdaptor.sol`, `BalancerPoolAdaptor.sol` (from Sommelier Protocol), `Interfaces`, etc.
- [ ] Add in foundry to start developing tests to work with standalone ERC4626s, etc. and simplest pricing mechanics
- [ ] Create docs outlining how to use the adaptor, though it should be just a one pager since the adaptor and interface should be well written for developers

# **Discussion Topics**

The purpose of this repo is to facilitate productive conversations around open-source ERC4626 development. Questions are to be discussed async within "Issues" or informally within the private TG chat. Reach out to 0xEinCodes if you are interested in being involved with general, open-source ERC 4626 Adaptor work with this initiative.
