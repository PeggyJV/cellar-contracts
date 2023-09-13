# Plain English Function Descriptions

This document provides high level details on how the "universal adaptor" code would work with others yield aggregator code, and "Plain English Function Desriptions."

It serves as a quick reference point versus digging into the interface file, `IBalancerStablePoolAdaptor.sol`, and/or the example implementation file `BalancerStablePoolAdaptor.sol`. Feel free to skip to those files and see their nat spec accordingly.

Please read the `README.md` within this sub-directory for context of the work associated to this document.

---

## Function Breakdown

This PR is starting with the idea of a "Universal Adaptor" for integrating into the Balancer protocol. Currently the idea is to:

- Have different interfaces and base implementation smart contracts to integrate into the respective Balancer Pool Type. There are various pool types in Balancer.
- Focus on integration into a Stable Pool type.

Thus, the `IBalancerStablePoolAdaptor.sol` functions will be broken down below.

### 

Function Name:

Description:

Dependencies:

Output: