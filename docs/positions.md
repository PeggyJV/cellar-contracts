# Positions

A Position is an instantiation of an adapter for a specific asset. A cellar may have multiple positions using the same adapter.

The process for setting up a position is as follows:

1. A cellar add an adapter that has been trusted by Registry with `AddAdapterToCatalogue`,
2. A cellar adds a position that has been trusted by Registry with `AddAdapterToCatalogue`
3. `AddPosition` places the position in the internal index and passes configuration data to the adapter. This is connected to things like holding position, withdrawal order, etc.
