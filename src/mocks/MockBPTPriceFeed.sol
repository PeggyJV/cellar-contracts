// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Math } from "src/utils/Math.sol";
import { ERC20, SafeTransferLib } from "src/base/ERC4626.sol";
import { IWstEth } from "src/interfaces/external/IWstEth.sol";

/**
 * @title Mock Balancer Pool Token (bpt) Price Feed
 * @notice Copied from WstETHExtension.sol. Provides a specific mock (and incorrect) bpt price feed abiding by Chainlink price feed requirements (ETH/STETH --> ex. .999 ETH / 1 STETH). This is essentially saying that instead of ETH/STETH, it's ETH/BPT. It is not necessary to create a close-to-accurate mock pricing source since we are bringing in PriceRouterV2 upgrades in this same audit round.
 * @dev As mentinoed, this is temporary while Sommelier PriceRouterV2 is being created and audited. PricerRouterV2 will have bpt specific extension ontracts for price sourcing.
 * @author crispymangoes & 0xEinCodes
 */
contract MockBPTPriceFeed {
    /**
     * @notice MOCK BPT:ETH contract --> really just ETH Mainnet WSTETH contract.
     */
    IWstEth public wstEth = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    uint256 public constant BPT_ETH_MOCKPRICE = 1; // TODO: Change if desired to test different mock test constants for bpt-price *approximate* conversions.

    uint256 public constant BPT_ETH_DECIMALS = 0; // TODO: Change if desired to test different mock test constants for bpt-price *approximate* conversions.

    /**
     * @notice STETH to ETH Chainlink datafeed.
     * @dev https://data.chain.link/ethereum/mainnet/crypto-eth/steth-eth
     */
    IChainlinkAggregator public STETH_ETH = IChainlinkAggregator(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    constructor() {}

    /**
     * @notice Returns the ETH/STETH datafeed's aggregator.
     */
    function aggregator() external view returns (address) {
        return STETH_ETH.aggregator();
    }

    /**
     * @notice Returns ETH per WSTETH.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _getLatest();
    }

    /**
     * @notice Returns ETH per WSTETH.
     */
    function latestAnswer() external view returns (int256 answer) {
        (, answer, , , ) = _getLatest();
    }

    /**
     * @notice Helper function to derive the bb-a-USD BPT/ETH price.
     * @dev Uses the ETH/STETH datafeed, and mock BPT_ETH_MOCKPRICE, AND BPT_ETH_DECIMALS
     */
    function _getLatest()
        internal
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = STETH_ETH.latestRoundData(); // ETH/STETH --> ex. .999 ETH / 1 STETH

        answer = (answer * int256(BPT_ETH_MOCKPRICE) / int256(10 ** BPT_ETH_DECIMALS)); // WANT --> ETH / 1 BPT -> get that by: ETH / STETH * 1 STETH / X BPT
        
    }
}