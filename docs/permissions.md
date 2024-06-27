# Permississons in Cellars.


## Cellars

The basic Cellar contract uses the Auth contract from solmate for permissioning. A typical deployment transfers authorization to either Axelar Proxy Contract or the Sommelier Gravity contract that then manages the permissions for the Cellar.

Sommelier chain has a complex permissioning system which can isolate calls to requiring either messagages from the strategist to the Sommelier validators which are typicallly executed in 1-5 min or calls that require a full 48-hour vote of the Sommelier token holders.

One key thing to note is that Cellars often hold complex defi positions that are non-trivial to unwind. Even if a Cellar is in the Shutdown state, there still needs to be a mechanism to execute trades that unwind the complex positions in an intelligent way.

## Registry

The Registry contract is typically managed by a multisig (Gnosis Safe). The registry is a contract that holds the addresses of all the adapters that the Cellar will use. Typically, adding a new adapter to the cellar requires both the multisig on the Registry and Sommelier governance to approve the change. The Registry makes it so the Cellar will trust the new adapter, and Sommelier governance makes the new adapter callable by the strategist.

## PriceRouter

Prices are a very sensitive security boundary in the Cellar. if the strategist tends keep funds in adapters that are not directly withdrawalable from then catastrophic pricing exploits are unlikely. Never the less, the Price Router is responsible for getting the price of assets supported by the Cellars so deposits and withdrawls can be priced correctly. This is typically also managed by the multisig. The current deployment of the PriceRouter is set up with a 7 day timelock on changes to decrease the risk of a sudden change to share pricing.
