// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

interface WstEth {
    function stEthPerToken() external view returns (uint256);

    function decimals() external view returns (uint8);
}

contract WstEthExtension {
    WstEth public wstEth = WstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

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
     * @dev Uses the ETH/STETH datafeed, and Lido Wrapped Steth to Steth conversion rate.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = STETH_ETH.latestRoundData();

        answer = (answer * int256(wstEth.stEthPerToken())) / int256(10 ** wstEth.decimals());
    }
}
