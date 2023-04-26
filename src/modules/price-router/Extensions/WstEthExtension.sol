// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Extension, PriceRouter, ERC20, Math } from "src/modules/price-router/Extensions/Extension.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

interface STETH {
    function getPooledEthByShares(uint256 shares) external view returns (uint256);

    function decimals() external view returns (uint8);
}

contract WstEthExtension is Extension {
    using Math for uint256;

    constructor(PriceRouter _priceRouter) Extension(_priceRouter) {}

    STETH public stEth = STETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /**
     * @notice STETH to ETH Chainlink datafeed.
     * @dev https://data.chain.link/ethereum/mainnet/crypto-eth/steth-eth
     */
    IChainlinkAggregator public STETH_ETH = IChainlinkAggregator(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    function setupSource(ERC20 asset, bytes memory) external view override onlyPriceRouter {
        require(address(asset) == wstEth, "Wrong asset");
        if (!priceRouter.isSupported(ERC20(address(stEth)))) revert("stEth must be supported.");
    }

    function getPriceInUSD(ERC20) external view override returns (uint256) {
        return
            stEth.getPooledEthByShares(1e18).mulDivDown(
                priceRouter.getPriceInUSD(ERC20(address(stEth))),
                10 ** stEth.decimals()
            );
    }
}
