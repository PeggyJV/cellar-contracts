# 🍷🏊🏻‍♀️ Balancer Universal Adaptor Project Details | _(AKA Join-The-Pool-The-Water's-Warm Project Details)_

> \*\*tl;dr - THE PURPOSE OF THIS REPO IS TO FACILITATE DISCUSSION AROUND A UNIVERSAL BALANCER POOL ADAPTOR. THIS PR FOCUSES ON USING A STABLEPOOL ADAPTOR AS THE FIRST EXAMPLE AS OTHER ADAPTORS CAN BE CREATED FOR DIFFERENT POOL TYPES. The end result will be an interface, and implementation code w/ a couple specific virtual (override-able) functions for bespoke aspects per Yield Aggregator project (such as pricing, whitelisting mutative contracts, etc.).

> Questions are to be discussed async within "Issues" or informally within the private Telegram chat. Reach out to 0xEinCodes (@EinCodes on Telegram) if you are interested in being involved with general, open-source ERC 4626 Adaptor work with this initiative.\*\*

> _Also, this is a wip integration. None of this code or concepts are to be used, and are not finalized (thus the TODOs scattered through the markdown right now)._

This means that deliverables include:

1. An interface, `IStablePoolAdaptor.sol`, that can be used to access any variation of StablePoolAdaptor that ends up being made by whomever. This allows forks or soft forks of projects to use pre-existing adaptors for any number of protocols.

2. A usable implementation contract, `BalancerStablePoolAdaptor.sol`, that has `internal virtual` helper functions that can be overridden so different projects can implement their own specific implementation code while still adhering / saving time with this pre-existing code via inheritance.
   NOTE: projects ought to include proper `Pricing` && `Registry` solution are specified within the accompanying code for a yield aggregator project. Yield Aggregator projects could choose to ignore the need for pricing and a registry, and simply use the adaptor to access specified Stable Pools. How Yield Aggregator projects choose to use this code is up to them. Thus when Yield Aggregator projects or any project use this `StablePoolAdaptor.sol`, they will likely need an audit and further testing for their specific use cases and architecture. Key aspects to keep in mind for other project's using this adaptor:

If this scope of work (the interface and implementation code for a Stable Pool Adaptor) are approved by the Balancer Grants Committee, then an audit will be carried out to finalize the code to be useable by other protocols in their own bespoke architectures.

# **TODOs:**

- [x] Create PR with: `IBalancerStablePoolAdaptor.sol`, `BalancerPoolAdaptor.sol` (from Sommelier Protocol), `Interfaces`, etc.
- [ ] Collect feedback from other yield aggregators on the design and usefulness, and assess the viability of this project getting a Balancer Grant and proceeding or not.
- [ ] Add in foundry to start developing tests to work with standalone ERC4626s, etc. and simplest pricing mechanics
- [ ] Create docs outlining how to use the adaptor, though it should be just a one pager since the adaptor and interface should be well written for developers

---

# **General Info and Disclaimer**

This PR serves as a starting point for developing open-source ERC 4626 Adaptors pertaining to specific protocols. These are a work in progress and are unaudited so use at your own risk. The aim is to have numerous protocol integration contracts documented and to lower the barrier to entry for projects using ERC 4626 Vaults from integrating with said protocols.

This PR is starting with the idea of a "Universal Adaptor" for integrating into the Balancer protocol. Currently the idea is to:

- Have different interfaces and base implementation smart contracts to integrate into the respective Balancer Pool Type. There are various pool types in Balancer.
- Focus on integration into a Stable Pool type.
