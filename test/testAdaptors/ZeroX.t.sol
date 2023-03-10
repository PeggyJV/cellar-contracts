// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";
import { EulerDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarZeroXTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    ERC20Adaptor private erc20Adaptor;
    ZeroXAdaptor private zeroXAdaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint32 private usdcPosition;
    uint32 private wethPosition;

    // Swap Details
    address private spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address private swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    bytes private swapCallData =
        hex"7a1eb1b9000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000e8d4a51000000000000000000000000000000000000000000000000020964af0d7305ca7db0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000d6ebac0ec50000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000011e8f9013c00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000042a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000064dac17f958d2ee523a2206206994597c13d831ec70001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000bc76e6b1f363e159a7";

    function setUp() external {
        erc20Adaptor = new ERC20Adaptor();
        zeroXAdaptor = new ZeroXAdaptor();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(zeroXAdaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH), 0, 0);

        positions[0] = usdcPosition;
        positions[1] = wethPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs;

        cellar = new Cellar(
            registry,
            USDC,
            "0x Cellar",
            "0x-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                usdcPosition,
                address(0),
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.setupAdaptor(address(zeroXAdaptor));

        cellar.setRebalanceDeviation(0.01e18);

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function test0xSwap() external {
        if (block.number < 16571863) {
            console.log("Invalid block number use 16571863");
            return;
        }
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSwap(USDC, assets, swapCallData);

            data[0] = Cellar.AdaptorCall({ adaptor: address(zeroXAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar USDC should have been converted into WETH.");
        uint256 expectedWETH = priceRouter.getValue(USDC, assets, WETH);
        assertApproxEqRel(
            WETH.balanceOf(address(cellar)),
            expectedWETH,
            0.01e18,
            "Cellar WETH should be approximately equal to expected."
        );
    }

    function testMaliciousSwapData() external {
        if (block.number < 16571863) {
            console.log("Invalid block number use 16571863");
            return;
        }
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        bytes memory fakeData = abi.encodeWithSignature("stealFunds(address,uint256)", address(USDC), assets);

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSwap(USDC, assets, fakeData);

            data[0] = Cellar.AdaptorCall({ adaptor: address(zeroXAdaptor), callData: adaptorCalls });
            vm.expectRevert(
                bytes(
                    abi.encodeWithSelector(
                        Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector,
                        0,
                        assets.mulDivDown(0.99e18, 1e18),
                        assets.mulDivDown(1.01e18, 1e18)
                    )
                )
            );
            cellar.callOnAdaptor(data);
        }
    }

    function stealFunds(address asset, uint256 amount) public {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function testResettingUnusedApprovals() external {
        if (block.number < 16571863) {
            console.log("Invalid block number use 16571863");
            return;
        }
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        bytes memory fakeData = abi.encodeWithSignature("doNothing(uint256)", 0);

        address fakeSpender = vm.addr(1);

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSwap(USDC, assets, fakeData);

            data[0] = Cellar.AdaptorCall({ adaptor: address(zeroXAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertEq(USDC.allowance(address(cellar), fakeSpender), 0, "Allowance should have been zeroed out.");
    }

    function doNothing(uint256) external {}

    function _createBytesDataToSwap(
        ERC20 tokenIn,
        uint256 amount,
        bytes memory _swapCallData
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ZeroXAdaptor.swapWith0x.selector, tokenIn, amount, _swapCallData);
    }
}
