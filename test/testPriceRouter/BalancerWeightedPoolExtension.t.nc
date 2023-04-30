// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { Registry } from "src/Registry.sol";

import { BalancerWeightedPoolExtension } from "src/modules/price-router/Extensions/BalancerWeightedPoolExtension.sol";

// import { IVault, VaultReentrancyLib } from "@balancer/pool-utils/contracts/lib/VaultReentrancyLib.sol";
import { IVault } from "@balancer/interfaces/contracts/vault/IVault.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract BalancerWeightedPoolExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    PriceRouter private priceRouter;

    // Deploy the extension.
    BalancerWeightedPoolExtension private balancerWeightedPoolExtension;

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Valid Derivatives
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant TWAP_DERIVATIVE = 2;
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant RPL = ERC20(0xD33526068D116cE69F19A9ee46F0bd304F21A51f);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;

    // UniV3 WETH/RPL Pool
    address private WETH_RPL_03_POOL = 0xe42318eA3b998e8355a3Da364EB9D48eC725Eb45;

    // Balancer BPTs
    ERC20 private RETH_RPL_BPT = ERC20(0x9F9d900462492D4C21e9523ca95A7CD86142F298);

    IVault private vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    Registry private registry;

    function setUp() external {
        registry = new Registry(address(this), address(this), address(this));

        priceRouter = new PriceRouter(registry);

        balancerWeightedPoolExtension = new BalancerWeightedPoolExtension(priceRouter, vault);

        // Setup chainlink pricing.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        stor.inETH = true;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        price = price.mulDivDown(uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer()), 1e18);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // Setup TWAP pricing.
        settings = PriceRouter.AssetSettings(TWAP_DERIVATIVE, WETH_RPL_03_POOL);
        PriceRouter.TwapSourceStorage memory twapStor = PriceRouter.TwapSourceStorage({
            secondsAgo: 900,
            baseDecimals: 18,
            quoteDecimals: 18,
            quoteToken: WETH
        });
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 41.86e8);

        // UniswapV3Pool(WETH_RPL_03_POOL).increaseObservationCardinalityNext(3_600);
    }

    // ======================================= HAPPY PATH =======================================
    function testPricingRethRplBpt() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(balancerWeightedPoolExtension)
        );
        priceRouter.addAsset(RETH_RPL_BPT, settings, abi.encode(0), 100e8);
    }
}
