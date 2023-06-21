// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { CellarAdaptor, BaseAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import { MockOneInchAdaptor } from "src/mocks/adaptors/MockOneInchAdaptor.sol";

contract CellarAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    ERC20Adaptor private erc20Adaptor;
    CellarAdaptor private cellarAdaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint32 private usdcPosition;
    uint32 private wethPosition;
    uint32 private cellarPosition;

    function setUp() external {
        erc20Adaptor = new ERC20Adaptor();
        cellarAdaptor = new CellarAdaptor();
        priceRouter = new PriceRouter(registry, WETH);
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
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(cellarAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));

        positions[0] = usdcPosition;
        positions[1] = wethPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs;

        cellar = new Cellar(
            registry,
            USDC,
            "Dummy Cellar",
            "Dummy-CLR",
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

        cellar.setRebalanceDeviation(0.01e18);

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testUsingIlliquidCellarPosition() external {
        cellarPosition = registry.trustPosition(address(cellarAdaptor), abi.encode(address(cellar)));

        uint32[] memory positions = new uint32[](1);
        uint32[] memory debtPositions;

        positions[0] = cellarPosition;

        bytes[] memory positionConfigs = new bytes[](1);
        positionConfigs[0] = abi.encode(false);
        bytes[] memory debtConfigs;

        Cellar metaCellar = new Cellar(
            registry,
            USDC,
            "Meta Cellar",
            "Meta-CLR",
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, cellarPosition)
        );

        metaCellar.addAdaptorToCatalogue(address(cellarAdaptor));

        USDC.safeApprove(address(metaCellar), type(uint256).max);

        // Deposit into meta cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);

        metaCellar.deposit(assets, address(this));

        uint256 assetsDeposited = cellar.totalAssets();
        assertEq(assetsDeposited, assets, "All assets should have been deposited into cellar.");

        uint256 liquidAssets = metaCellar.maxWithdraw(address(this));
        assertEq(liquidAssets, 0, "Meta Cellar should have no liquid assets since it is configured to be illiquid.");

        // Check logic in the withdraw function by having strategist call withdraw, passing in isLiquid = false.
        bool isLiquid = false;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CellarAdaptor.withdraw.selector,
            assets,
            address(this),
            abi.encode(cellar),
            abi.encode(isLiquid)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        metaCellar.callOnAdaptor(data);
    }
}
