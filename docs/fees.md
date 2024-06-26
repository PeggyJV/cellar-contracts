# Fees

Strategists use the Fees and Reserve system to manage the fees generated by the cellar. The fees are generated by the cellar's strategies and are denominated in the holding asset. The plaform cut is managed directly in the Cellar and is a fraction of the total fees generated by the Strategist.

## Reseve

The Reserve is an adapter the hold funds from the cellar. Generally the strategist moves funds into the reserve on a regular basis from profits. The reserve gives the stratgist optionality. Fees must be collected from the reserve but funds in the reserve can also be returned to the cellar if the strategist decides to do so.

## Fees

Fees are storied in the metadata strct of the fees and reserves module. The management fees are computed on NAV and stored as basis points. The peformance fees are computed by tracking a highwater mark of the share from from each fee collection and then computing the fees based on the growth of the share price. New LP shares are minted when the performance fee is collected and that effectively dilutes the existing LPs.

  ``` solidity

  /**
       * @notice Stores meta data needed to calculate a calling cellars earned fees.
       * @dev Store calling Cellars meta data in this contract to help mitigate malicious external contracts
       *         attempting to break logic by illogically changing meta data values.
       * @param reserveAsset ERC20 asset Cellar does all its accounting in
       * @param managementFee Fee charged for managing a Cellar's assets
       *        - Based off basis points, so 100% would be 1e4
       * @param timestamp The last time this cellar had it's fees calculated
       * @param reserves The amount of `reserveAsset` a Cellar has available to it
       * @param exactHighWatermark High Watermark normalized to 27 decimals
       * @param totalAssets Stored total assets
       *        - When calculating fees this value is compared against the current Total Assets, and the minimum value is used
       * @param feesOwed The amount of fees this cellar has accumulated from both performance and management fees
       * @param cellarDecimals Number of decimals Cellar Shares have
       * @param reserveAssetDecimals Number of decimals the `reserveAsset` has
       * @param performanceFee Fee charged based off a cellar share price growth
       *        - Based off basis points, so 100% would be 1e4
       */
      struct MetaData {
          ERC20 reserveAsset;
          uint32 managementFee;
          uint64 timestamp;
          uint256 reserves;
          uint256 exactHighWatermark;
          uint256 totalAssets;
          uint256 feesOwed;
          uint8 cellarDecimals;
          uint8 reserveAssetDecimals;
          uint32 performanceFee;
      }
  ```

  ## Platform Fees

  When the strategist withdraw fees from the Cellar, the top level platform fee takes a cut for the Sommelier protocol. These fees are sent to the Sommelier chain via the gravity bridge on Ethereum mainnet and the Axelar on other chains. The fees are then auctioned to generate staking rewards.

  It's expected that Strategists will collect fees every two weeks and trigger auctions on the Somm chain periodically.
