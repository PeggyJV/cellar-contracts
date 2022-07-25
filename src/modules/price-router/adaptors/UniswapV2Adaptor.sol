// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "src/interfaces/IChainlinkAggregator.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "src/utils/Math.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IUniswapV2Pair } from "src/interfaces/IUniswapV2Pair.sol";

contract UniswapV2Adaptor {
    using SafeCast for int256;
    using Math for uint256;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // =========================================== HELPER FUNCTIONS ===========================================
    //assumes msg.sender is the price router
    function getValueInUSDAndTimestamp(ERC20 asset) external view returns (uint256 price, uint256 timestamp) {
        IUniswapV2Pair pair = IUniswapV2Pair(address(asset));

        ERC20 token0 = ERC20(pair.token0());
        ERC20 token1 = ERC20(pair.token1());
        ERC20[] memory baseAssets = new ERC20[](2);
        uint256[] memory amounts = new uint256[](2);
        baseAssets[0] = token0;
        baseAssets[1] = token1;
        amounts[0] = token0.balanceOf(address(pair));
        amounts[1] = token1.balanceOf(address(pair));

        PriceRouter router = PriceRouter(msg.sender);
        //price = (router.getValues(baseAssets, amounts, USDC) * 1e20) / pair.totalSupply(); // 20 = 2(for the USDC to USD) + 18 for the LP token decimals

        price = token0.balanceOf(address(pair)).mulDivDown(router.getValueInUSD(token0), 10**token0.decimals());
        price += token1.balanceOf(address(pair)).mulDivDown(router.getValueInUSD(token1), 10**token1.decimals());
        price = price.mulDivDown(1e18, pair.totalSupply());

        //could change price router to ignore timestamp check if timestamp is zero?
        timestamp = block.timestamp;

        //TODO add checks for ratio between tokens 0, 1, kLast and fair LP pricing
    }
}
