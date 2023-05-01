// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Registry } from "src/Registry.sol";

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract WstEthExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    PriceRouter private priceRouter;

    // Deploy the extension.
    WstEthExtension private wstethExtension;

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Valid Derivatives
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant TWAP_DERIVATIVE = 2;
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 private constant WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    Registry private registry;

    function setUp() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        registry = new Registry(address(this), address(this), address(this));

        priceRouter = new PriceRouter(registry);
        wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }

    // ======================================= HAPPY PATH =======================================
    function testWstEthExtension() external {
        // Setup dependent price feeds.
        PriceRouter.AssetSettings memory settings;
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add wstEth.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        assertApproxEqRel(
            priceRouter.getValue(WSTETH, 1e18, STETH),
            wstethToStethConversion,
            1e8,
            "WSTETH value in STETH should approx equal conversion."
        );
    }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        // Add wstEth.
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));

        address notWSTETH = vm.addr(123);
        vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__ASSET_NOT_WSTETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    }

    function testAddingWstethWithoutPricingSteth() external {
        // Add wstEth.
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        vm.expectRevert(bytes(abi.encodeWithSelector(WstEthExtension.WstEthExtension__STETH_NOT_SUPPORTED.selector)));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);
    }
}
