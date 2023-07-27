// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { StEthExtension } from "src/modules/price-router/Extensions/Lido/StEthExtension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { CurveNgPool } from "src/interfaces/external/Curve/CurveNgPool.sol";
import { OracleLibrary } from "@uniswapV3P/libraries/OracleLibrary.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract StEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    MockDataFeed private stethMockFeed;

    StEthExtension private stethExtension;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17786532;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        stethMockFeed = new MockDataFeed(STETH_ETH_FEED);

        stethExtension = new StEthExtension(
            priceRouter,
            50,
            WSTETH_WETH_500,
            address(stethMockFeed),
            1 days,
            address(WETH),
            address(STETH),
            1 days / 4
        );

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
    function testStEthExtension() external {
        // Setup dependent price feeds.
        PriceRouter.AssetSettings memory settings;

        // Add stEth.
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stethExtension));
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        assertApproxEqRel(
            priceRouter.getValue(STETH, 1e18, WETH),
            1e18,
            0.001e18,
            "STETH value in WETH should approx equal 1:1."
        );
    }

    // function testAnswersDiverging() external {
    //     // Add stEth.
    //     uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
    //     PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
    //         EXTENSION_DERIVATIVE,
    //         address(stethExtension)
    //     );
    //     priceRouter.addAsset(STETH, settings, abi.encode(0), price);

    //     uint256 chainlinkAnswer = stethExtension.getAnswerFromChainlink();
    //     uint256 curveAnswer = stethExtension.getAnswerFromCurve();

    //     // Price is not diverged, so extension should use curve answer.
    //     uint256 stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
    //     uint256 curveAnswerInUsdc = priceRouter.getValue(WETH, curveAnswer, USDC);
    //     assertEq(
    //         stethPriceInUsdc,
    //         curveAnswerInUsdc,
    //         "Low Answer divergence, should have made oracle use Curve Answer"
    //     );

    //     // Deviate chainlink answer up 51bps above curve answer.
    //     // Deviation makes chainlink answer report a value greater than 1:1 peg, so extension should default to use 1:1.
    //     // TODO this was commented out for now
    //     chainlinkAnswer = curveAnswer.mulDivDown(1.0051e4, 1e4);

    //     stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

    //     stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
    //     uint256 chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
    //     assertEq(
    //         stethPriceInUsdc,
    //         chainlinkAnswerInUsdc,
    //         "Answer divergence, should have made oracle use Chainlink Answer"
    //     );

    //     // Deviate chainlink answer to 51bps below curve answer.
    //     chainlinkAnswer = curveAnswer.mulDivDown(0.9949e4, 1e4);

    //     stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

    //     stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
    //     chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
    //     assertEq(
    //         stethPriceInUsdc,
    //         chainlinkAnswerInUsdc,
    //         "Answer divergence, should have made oracle use Chainlink Answer"
    //     );

    //     // Minor deviations do not trigger oracle to use Chainlink answer.
    //     chainlinkAnswer = curveAnswer.mulDivDown(1.0010e4, 1e4);

    //     stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

    //     stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
    //     assertEq(
    //         stethPriceInUsdc,
    //         curveAnswerInUsdc,
    //         "Low Answer divergence, should have made oracle use Curve Answer"
    //     );

    //     // Deviate chainlink answer to 51bps below curve answer.
    //     chainlinkAnswer = curveAnswer.mulDivDown(0.9990e4, 1e4);

    //     stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

    //     stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
    //     assertEq(
    //         stethPriceInUsdc,
    //         curveAnswerInUsdc,
    //         "Low Answer divergence, should have made oracle use Curve Answer"
    //     );
    // }

    // ======================================= REVERTS =======================================
    function testUsingExtensionWithWrongAsset() external {
        // Add wstEth.
        PriceRouter.AssetSettings memory settings;

        address notWSTETH = vm.addr(123);
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stethExtension));
        vm.expectRevert(bytes(abi.encodeWithSelector(StEthExtension.StEthExtension__ASSET_NOT_STETH.selector)));
        priceRouter.addAsset(ERC20(notWSTETH), settings, abi.encode(0), price);
    }

    function testChainlinkReverts() external {
        // Add stEth.
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(stethExtension)
        );
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        // Chainlink answer becomes stale.
        stethMockFeed.setMockUpdatedAt(block.timestamp - (1 days + 1));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(StEthExtension.StEthExtension__StalePrice.selector, (1 days + 1), 1 days))
        );
        priceRouter.getPriceInUSD(STETH);

        stethMockFeed.setMockUpdatedAt(block.timestamp);

        // Chainlink answer negative.
        stethMockFeed.setMockAnswer(-1);

        vm.expectRevert(bytes(abi.encodeWithSelector(StEthExtension.StEthExtension__ZeroOrNegativePrice.selector)));
        priceRouter.getPriceInUSD(STETH);

        // Reset back to normal.
        stethMockFeed.setMockAnswer(0);

        // Calls work.
        priceRouter.getPriceInUSD(STETH);
    }
}
