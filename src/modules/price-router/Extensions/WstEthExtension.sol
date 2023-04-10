// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { IWstEth } from "src/interfaces/external/IWstEth.sol";

/**
 * @title Sommelier WstEth pricing extension
 * @notice Allows V1 Price Router to price WstEth as if there were a WSTETH ETH Chainlink Oracle.
 * @author crispymangoes
 */
contract WstEthExtension {
    /**
     * @notice ETH Mainnet WSTETH contract.
     */
    IWstEth public wstEth = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

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
     * @notice Helper function to derive the WSTETH ETH price.
     * @dev Uses the ETH/STETH datafeed, and Lido Wrapped Steth to Steth conversion rate.
     */
    function _getLatest()
        internal
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = STETH_ETH.latestRoundData();

        answer = (answer * int256(wstEth.stEthPerToken())) / int256(10 ** wstEth.decimals());
    }
}
