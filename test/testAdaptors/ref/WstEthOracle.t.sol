// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.16;

// import { ERC20 } from "src/base/ERC20.sol";
// import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
// import { IAaveOracle } from "src/interfaces/external/IAaveOracle.sol";
// import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
// import { WstEthExtension } from "src/modules/price-router/Extensions/WstEthExtension.sol";

// import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
// import { Math } from "src/utils/Math.sol";

// contract WstEthOracleTest is Test {
//     using Math for uint256;
//     using stdStorage for StdStorage;

//     PriceRouter private immutable priceRouter = new PriceRouter();
//     WstEthExtension private wstEthOracle;

//     address private immutable sender = vm.addr(0xABCD);
//     address private immutable receiver = vm.addr(0xBEEF);

//     // Valid Derivatives
//     uint8 private constant CHAINLINK_DERIVATIVE = 1;

//     // Mainnet contracts:
//     ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
//     ERC20 private constant WstEth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
//     ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
//     IAaveOracle private aaveOracle = IAaveOracle(0x54586bE62E3c3580375aE3723C145253060Ca0C2);

//     // Chainlink PriceFeeds
//     address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
//     address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

//     function setUp() external {
//         // Ignore if not on mainnet.
//         if (block.chainid != 1) return;

//         wstEthOracle = new WstEthExtension();

//         PriceRouter.ChainlinkDerivativeStorage memory stor;

//         PriceRouter.AssetSettings memory settings;

//         uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
//         settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
//         priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

//         settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
//         priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
//     }

//     // ======================================= ASSET TESTS =======================================
//     function testAddWstEthAssetAndComparePriceToAaveOracle() external {
//         PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
//             CHAINLINK_DERIVATIVE,
//             address(wstEthOracle)
//         );
//         PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
//             90e18,
//             0.1e18,
//             0,
//             true
//         );
//         uint256 price = uint256(wstEthOracle.latestAnswer());
//         price = priceRouter.getValue(WETH, price, USDC);
//         price = price.changeDecimals(6, 8);
//         priceRouter.addAsset(WstEth, settings, abi.encode(stor), price);

//         (uint144 maxPrice, uint80 minPrice, uint24 heartbeat, bool isETH) = priceRouter.getChainlinkDerivativeStorage(
//             WstEth
//         );

//         assertTrue(isETH, "WstEth data feed should be in ETH");
//         assertEq(minPrice, 0.1e18, "Should set min price");
//         assertEq(maxPrice, 90e18, "Should set max price");
//         assertEq(heartbeat, 1 days, "Should set heartbeat");
//         assertTrue(priceRouter.isSupported(WstEth), "Asset should be supported");

//         uint256 priceInUsdc = priceRouter.getValue(WstEth, 1e18, USDC);
//         uint256 priceInWeth = priceRouter.getValue(WstEth, 1e18, WETH);

//         uint256 expectedWstEthPriceInBase = aaveOracle.getAssetPrice(address(WstEth));
//         uint256 expectedPriceInUsdc = expectedWstEthPriceInBase.mulDivDown(
//             1e6,
//             aaveOracle.getAssetPrice(address(USDC))
//         );

//         uint256 expectedPriceInWeth = expectedWstEthPriceInBase.mulDivDown(
//             1e18,
//             aaveOracle.getAssetPrice(address(WETH))
//         );

//         assertApproxEqRel(
//             priceInUsdc,
//             expectedPriceInUsdc,
//             0.00000000001e18,
//             "WstEth USDC conversion differs greatly from Aave."
//         );
//         assertApproxEqRel(
//             priceInWeth,
//             expectedPriceInWeth,
//             0.00000000001e18,
//             "WstEth WETH conversion differs greatly from Aave."
//         );
//     }
// }