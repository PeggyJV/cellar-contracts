// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { StEthExtension } from "src/modules/price-router/Extensions/Lido/StEthExtension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { OracleLibrary } from "@uniswapV3P/libraries/OracleLibrary.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract StEthExtensionTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    MockDataFeed private stethMockFeed;

    StEthExtension private stethExtension;
    IUniswapV3Router public uniswapV3Router = IUniswapV3Router(uniV3Router);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17792292;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        stethMockFeed = new MockDataFeed(STETH_ETH_FEED);

        stethExtension = new StEthExtension(
            priceRouter,
            50,
            WSTETH_WETH_100,
            address(stethMockFeed),
            1 days,
            address(WETH),
            address(STETH),
            1 days / 4,
            1e25
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
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

    function testAnswersDiverging() external {
        // Add stEth.
        uint256 price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            EXTENSION_DERIVATIVE,
            address(stethExtension)
        );
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        uint256 chainlinkAnswer = stethExtension.getAnswerFromChainlink();
        uint256 uniswapAnswer = stethExtension.getAnswerFromUniswap();

        // Price is not diverged, so extension should use uniswap answer.
        uint256 stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        uint256 uniswapAnswerInUsdc = priceRouter.getValue(WETH, uniswapAnswer, USDC);
        assertEq(
            stethPriceInUsdc,
            uniswapAnswerInUsdc,
            "Low Answer divergence, should have made oracle use uniswap Answer"
        );

        // Deviate chainlink answer up 51bps above uniswap answer.
        // Deviation makes chainlink answer report a value greater than 1:1 peg, so extension should default to use 1:1.
        chainlinkAnswer = uniswapAnswer.mulDivDown(1.0051e4, 1e4);

        stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

        stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        uint256 cappedAnswerInUsdc = priceRouter.getValue(WETH, 1e18, USDC);
        assertEq(
            stethPriceInUsdc,
            cappedAnswerInUsdc,
            "Answer divergence, should have made oracle use Chainlink Answer"
        );

        // Deviate chainlink answer to 51bps below uniswap answer.
        chainlinkAnswer = uniswapAnswer.mulDivDown(0.9949e4, 1e4);

        stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

        stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        uint256 chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
        assertEq(
            stethPriceInUsdc,
            chainlinkAnswerInUsdc,
            "Answer divergence, should have made oracle use Chainlink Answer"
        );

        // Minor deviations do not trigger oracle to use Chainlink answer.
        chainlinkAnswer = uniswapAnswer.mulDivDown(1.0010e4, 1e4);

        stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

        stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        assertEq(
            stethPriceInUsdc,
            uniswapAnswerInUsdc,
            "Low Answer divergence, should have made oracle use uniswap Answer"
        );

        // Deviate chainlink answer to 51bps below uniswap answer.
        chainlinkAnswer = uniswapAnswer.mulDivDown(0.9990e4, 1e4);

        stethMockFeed.setMockAnswer(int256(chainlinkAnswer));

        stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        assertEq(
            stethPriceInUsdc,
            uniswapAnswerInUsdc,
            "Low Answer divergence, should have made oracle use uniswap Answer"
        );
    }

    function testUniswapOracleFailuresDefaultingToChainlinkIfObservationsToNew() external {
        // Go back in time to when TWAP did not have enough observations.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17773179;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        stethMockFeed = new MockDataFeed(STETH_ETH_FEED);

        // Deploy extension, but make duration 12 hours.
        stethExtension = new StEthExtension(
            priceRouter,
            50,
            WSTETH_WETH_100,
            address(stethMockFeed),
            1 days,
            address(WETH),
            address(STETH),
            1 days / 2,
            1e25
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        // Add stEth.
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stethExtension));
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        uint256 chainlinkAnswer = stethExtension.getAnswerFromChainlink();

        uint256 stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        uint256 chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
        assertEq(
            stethPriceInUsdc,
            chainlinkAnswerInUsdc,
            "Uniswap Observations too new, should have made oracle use Chainlink Answer"
        );
    }

    function testUniswapOracleFailuresDefaultingToChainlinkIfMeanLiquidityLow() external {
        // Go back in time and redeploy extension, but specify a much larger minimum mean liquidity.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17773179;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        stethMockFeed = new MockDataFeed(STETH_ETH_FEED);

        // Deploy extension, but make duration 12 hours.
        stethExtension = new StEthExtension(
            priceRouter,
            50,
            WSTETH_WETH_100,
            address(stethMockFeed),
            1 days,
            address(WETH),
            address(STETH),
            1 days / 4,
            1e26
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        // Add stEth.
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(stethExtension));
        priceRouter.addAsset(STETH, settings, abi.encode(0), price);

        uint256 chainlinkAnswer = stethExtension.getAnswerFromChainlink();

        uint256 stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        uint256 chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
        assertEq(
            stethPriceInUsdc,
            chainlinkAnswerInUsdc,
            "Uniswap Observations too new, should have made oracle use Chainlink Answer"
        );

        // NOTE below code is a much better test for this, but it takes a RIDICULOUS amount of time
        // to run it, so the above test was used instead.
        // // Drive price to low liquidity ticks
        // UniswapV3Pool pool = UniswapV3Pool(WSTETH_WETH_100);
        // address[] memory path = new address[](2);
        // path[0] = address(WSTETH);
        // path[1] = address(WETH);
        // uint24[] memory poolFees_100 = new uint24[](1);
        // poolFees_100[0] = 100;
        // uint256 swapAmount = 4_500e18;
        // bytes memory swapData = abi.encode(path, poolFees_100, swapAmount, 0);
        // deal(address(WSTETH), address(this), swapAmount);
        // swapWithUniV3(swapData, address(this), WSTETH);

        // assertGt(
        //     stethExtension.minimumMeanLiquidity(),
        //     pool.liquidity(),
        //     "Liquidity should have been driven to a low liquidity area."
        // );

        // // Advance time, and block number to ~6 hours in the future.
        // vm.warp(block.timestamp + (6 * 3_600));
        // vm.roll(block.number + 1);

        // // Make a swap to create an observation.
        // swapAmount = 1e18;
        // deal(address(WSTETH), address(this), swapAmount);
        // swapWithUniV3(swapData, address(this), WSTETH);

        // uint256 chainlinkAnswer = stethExtension.getAnswerFromChainlink();
        // uint256 uniswapAnswer = stethExtension.getAnswerFromUniswap();

        // console.log("chainlinkAnswer", chainlinkAnswer);
        // console.log("uniswapAnswer", uniswapAnswer);
        // uint256 stethPriceInUsdc = priceRouter.getValue(STETH, 1e18, USDC);
        // uint256 chainlinkAnswerInUsdc = priceRouter.getValue(WETH, chainlinkAnswer, USDC);
        // assertEq(
        //     stethPriceInUsdc,
        //     chainlinkAnswerInUsdc,
        //     "Uniswap Observations too new, should have made oracle use Chainlink Answer"
        // );
    }

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

    // ========================================= HELPER FUNCTIONS =========================================

    function swapWithUniV3(bytes memory swapData, address receiver, ERC20 assetIn) public returns (uint256 amountOut) {
        (address[] memory path, uint24[] memory poolFees, uint256 amount, uint256 amountOutMin) = abi.decode(
            swapData,
            (address[], uint24[], uint256, uint256)
        );

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(uniswapV3Router), amount);

        // Encode swap parameters.
        bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
        for (uint256 i = 1; i < path.length; i++)
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFees[i - 1], path[i]);

        // Execute the swap.
        amountOut = uniswapV3Router.exactInput(
            IUniswapV3Router.ExactInputParams({
                path: encodePackedPath,
                recipient: receiver,
                deadline: block.timestamp + 60,
                amountIn: amount,
                amountOutMinimum: amountOutMin
            })
        );
    }
}
