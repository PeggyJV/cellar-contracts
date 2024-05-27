// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {PriceRouter, Registry, ERC20, IChainlinkAggregator} from "src/modules/price-router/PriceRouter.sol";

/**
 * @title SequencerPriceRouter
 * @notice Adds sequencer uptime feed safety checks to all PriceRouter pricing calls.
 * @author crispymangoes
 */
contract SequencerPriceRouter is PriceRouter {
    //============================== ERRORS ===============================

    error SequencerPriceRouter__SequencerDown();
    error SequencerPriceRouter__GracePeriodNotOver();

    //============================== IMMUTABLES ===============================

    /**
     * @notice Address for the networks sequencer uptime feed.
     */
    IChainlinkAggregator internal immutable sequencerUptimeFeed;

    /**
     * @notice The amount of time that must pass from when the sequencer comes back online
     *         to when we can continue pricing again.
     */
    uint256 internal immutable gracePeriod;

    constructor(address _sequencerUptimeFeed, uint256 _gracePeriod, address newOwner, Registry _registry, ERC20 _weth)
        PriceRouter(newOwner, _registry, _weth)
    {
        sequencerUptimeFeed = IChainlinkAggregator(_sequencerUptimeFeed);
        gracePeriod = _gracePeriod;
    }

    //============================== Sequencer Uptime Logic ===============================

    /**
     * @notice Layer 2 chains that use sequencers, can have the sequencer go down. If this happens we do not want
     *         to price assets, as the datafeeds could be stale, and need to be updated.
     */
    function _runPreFlightCheck() internal view override {
        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();

        // This check should make TXs from L1 to L2 revert if someone tried interacting with the cellar while the sequencer is down.
        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        if (answer == 1) {
            revert SequencerPriceRouter__SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= gracePeriod) {
            revert SequencerPriceRouter__GracePeriodNotOver();
        }
    }
}
