// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ICurveFi } from "src/interfaces/external/ICurveFi.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { MockGasFeed } from "src/mocks/MockGasFeed.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CurveV1ExtensionTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    event AddAsset(address indexed asset);
    event RemoveAsset(address indexed asset);

    PriceRouter private immutable priceRouter = new PriceRouter(registry);

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
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private constant BOND = ERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);
    ERC20 private constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private constant FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 private constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 private constant WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IUniswapV2Router private constant uniV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Aave assets.
    ERC20 private constant aDAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    ERC20 private constant aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private constant aUSDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);

    // Curve Pools and Tokens.
    address private constant TriCryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    ERC20 private constant CRV_3_CRYPTO = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    address private constant daiUsdcUsdtPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    ERC20 private constant CRV_DAI_USDC_USDT = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address private constant frax3CrvPool = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    ERC20 private constant CRV_FRAX_3CRV = ERC20(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address private constant wethCrvPool = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    ERC20 private constant CRV_WETH_CRV = ERC20(0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d);
    address private constant aave3Pool = 0xDeBF20617708857ebe4F679508E7b7863a8A8EeE;
    ERC20 private constant CRV_AAVE_3CRV = ERC20(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);

    address public automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private BOND_ETH_FEED = 0xdd22A54e05410D8d1007c38b5c7A3eD74b855281;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address private ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

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

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        price = uint256(IChainlinkAggregator(BOND_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        priceRouter.addAsset(BOND, settings, abi.encode(stor), price);
    }

    // function testAddCurveAsset() external {
    //     PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
    //     uint256 vp = ICurvePool(TriCryptoPool).get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 1136.74e8);

    //     (uint96 datum, uint64 timeLastUpdated, uint32 posDelta, uint32 negDelta, uint32 rateLimit) = priceRouter
    //         .getVirtualPriceBound(address(CRV_3_CRYPTO));

    //     assertEq(datum, vp, "`datum` should equal the virtual price.");
    //     assertEq(timeLastUpdated, block.timestamp, "`timeLastUpdated` should equal current timestamp.");
    //     assertEq(posDelta, 1.01e8, "`posDelta` should equal 1.01.");
    //     assertEq(negDelta, 0.99e8, "`negDelta` should equal 0.99.");
    //     assertEq(rateLimit, priceRouter.DEFAULT_RATE_LIMIT(), "`rateLimit` should have been set to default.");
    // }


    // ======================================= CURVEv1 TESTS =======================================
    // function testCRV3Pool() external {
    //     // Add 3Pool to price router.
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(1.0224e8),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

    //     // Start by adding liquidity to 3Pool.
    //     uint256 amount = 1_000e18;
    //     deal(address(DAI), address(this), amount);
    //     DAI.approve(daiUsdcUsdtPool, amount);
    //     ICurveFi pool = ICurveFi(daiUsdcUsdtPool);
    //     uint256[3] memory amounts = [amount, 0, 0];
    //     pool.add_liquidity(amounts, 0);
    //     uint256 lpReceived = CRV_DAI_USDC_USDT.balanceOf(address(this));
    //     uint256 inputAmountWorth = priceRouter.getValue(DAI, amount, USDC);
    //     uint256 outputAmountWorth = priceRouter.getValue(CRV_DAI_USDC_USDT, lpReceived, USDC);
    //     assertApproxEqRel(
    //         outputAmountWorth,
    //         inputAmountWorth,
    //         0.01e18,
    //         "3CRV LP tokens should be worth DAI input +- 1%"
    //     );
    // }

    // function testCRVFrax3Pool() external {
    //     // Add 3Pool to price router.
    //     PriceRouter.AssetSettings memory settings;
    //     PriceRouter.ChainlinkDerivativeStorage memory stor;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
    //     ICurveFi pool = ICurveFi(daiUsdcUsdtPool);
    //     uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

    //     // Add FRAX to price router.
    //     settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
    //     priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

    //     // Add FRAX3CRV to price router.
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
    //     pool = ICurveFi(frax3CrvPool);
    //     vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
    //     priceRouter.addAsset(CRV_FRAX_3CRV, settings, abi.encode(vpBound), 1.0087e8);

    //     // Add liquidity to Frax 3CRV Pool.
    //     uint256 amount = 1_000e18;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
    //     deal(address(FRAX), address(this), amount);
    //     FRAX.approve(frax3CrvPool, amount);
    //     uint256[2] memory amounts = [amount, 0];
    //     pool.add_liquidity(amounts, 0);
    //     uint256 lpReceived = CRV_FRAX_3CRV.balanceOf(address(this));
    //     uint256 inputAmountWorth = priceRouter.getValue(FRAX, amount, USDC);
    //     uint256 outputAmountWorth = priceRouter.getValue(CRV_FRAX_3CRV, lpReceived, USDC);
    //     assertApproxEqRel(
    //         outputAmountWorth,
    //         inputAmountWorth,
    //         0.01e18,
    //         "Frax 3CRV LP tokens should be worth FRAX input +- 1%"
    //     );
    // }

    // function testCRVAave3Pool() external {
    //     // Add aDAI to the price router.
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aDAI));
    //     priceRouter.addAsset(aDAI, settings, abi.encode(0), 1e8);

    //     // Add aUSDC to the price router.
    //     settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aUSDC));
    //     priceRouter.addAsset(aUSDC, settings, abi.encode(0), 1e8);

    //     // Add aUSDT to the price router.
    //     settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aUSDT));
    //     priceRouter.addAsset(aUSDT, settings, abi.encode(0), 1e8);

    //     // Add Aave 3Pool.
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, aave3Pool);
    //     uint256 vp = ICurvePool(aave3Pool).get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_AAVE_3CRV, settings, abi.encode(vpBound), 1.0983e8);

    //     // Add liquidity to Aave 3 Pool.
    //     uint256 amount = 1_000e18;
    //     deal(address(DAI), address(this), amount);
    //     IPool aavePool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    //     DAI.approve(address(aavePool), amount);
    //     aavePool.deposit(address(DAI), amount, address(this), 0);
    //     amount = aDAI.balanceOf(address(this));
    //     aDAI.approve(aave3Pool, amount);
    //     ICurveFi pool = ICurveFi(aave3Pool);
    //     uint256[3] memory amounts = [amount, 0, 0];
    //     pool.add_liquidity(amounts, 0);
    //     uint256 lpReceived = CRV_AAVE_3CRV.balanceOf(address(this));

    //     // Check value in vs value out.
    //     uint256 inputAmountWorth = priceRouter.getValue(aDAI, amount, USDC);
    //     uint256 outputAmountWorth = priceRouter.getValue(CRV_AAVE_3CRV, lpReceived, USDC);
    //     assertApproxEqRel(
    //         outputAmountWorth,
    //         inputAmountWorth,
    //         0.01e18,
    //         "Aave 3 Pool LP tokens should be worth aDAI input +- 1%"
    //     );
    // }

    // function testCurveV1VirtualPriceBoundsCheck() external {
    //     // Add 3Pool to price router.
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(1.0224e8),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

    //     // Change virtual price to move it above upper bound.
    //     _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.90e18);
    //     uint256 currentVirtualPrice = ICurvePool(daiUsdcUsdtPool).get_virtual_price();
    //     (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
    //     uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
    //                 currentVirtualPrice,
    //                 upper
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_DAI_USDC_USDT, 1e18, USDC);

    //     // Change virtual price to move it below lower bound.
    //     _adjustVirtualPrice(CRV_DAI_USDC_USDT, 1.20e18);
    //     currentVirtualPrice = ICurvePool(daiUsdcUsdtPool).get_virtual_price();
    //     uint256 lower = uint256(datum).mulDivDown(0.99e8, 1e8).changeDecimals(8, 18);

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentBelowLowerBound.selector,
    //                 currentVirtualPrice,
    //                 lower
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_DAI_USDC_USDT, 1e18, USDC);
    // }

    // // ======================================= CURVEv2 TESTS =======================================
    // function testCRV3Crypto() external {
    //     // Add 3Crypto to the price router
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(1.0248e8),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 1136.74e8);

    //     // Start by adding liquidity to 3CRVCrypto.
    //     uint256 amount = 10e18;
    //     deal(address(WETH), address(this), amount);
    //     WETH.approve(TriCryptoPool, amount);
    //     ICurveFi pool = ICurveFi(TriCryptoPool);
    //     uint256[3] memory amounts = [0, 0, amount];
    //     pool.add_liquidity(amounts, 0);
    //     uint256 lpReceived = CRV_3_CRYPTO.balanceOf(address(this));
    //     uint256 inputAmountWorth = priceRouter.getValue(WETH, amount, USDC);
    //     uint256 outputAmountWorth = priceRouter.getValue(CRV_3_CRYPTO, lpReceived, USDC);
    //     assertApproxEqRel(
    //         outputAmountWorth,
    //         inputAmountWorth,
    //         0.01e18,
    //         "TriCrypto LP tokens should be worth WETH input +- 1%"
    //     );
    // }

    // function testCRVWETHCRVPool() external {
    //     // Add WETH CRV Pool to the price router
    //     ICurveFi pool = ICurveFi(wethCrvPool);
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
    //     uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), 87.66e8);

    //     // Start by adding liquidity to WETH CRV Pool.
    //     uint256 amount = 10e18;
    //     deal(address(WETH), address(this), amount);
    //     WETH.approve(wethCrvPool, amount);
    //     uint256[2] memory amounts = [amount, 0];
    //     pool.add_liquidity(amounts, 0);
    //     uint256 lpReceived = CRV_WETH_CRV.balanceOf(address(this));
    //     uint256 inputAmountWorth = priceRouter.getValue(WETH, amount, USDC);
    //     uint256 outputAmountWorth = priceRouter.getValue(CRV_WETH_CRV, lpReceived, USDC);
    //     assertApproxEqRel(
    //         outputAmountWorth,
    //         inputAmountWorth,
    //         0.01e18,
    //         "WETH CRV LP tokens should be worth WETH input +- 1%"
    //     );
    // }

    // function testCurveV2VirtualPriceBoundsCheck() external {
    //     // Add WETH CRV Pool to the price router
    //     ICurveFi pool = ICurveFi(wethCrvPool);
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
    //     uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), 87.66e8);

    //     // Change virtual price to move it above upper bound.
    //     _adjustVirtualPrice(CRV_WETH_CRV, 0.90e18);
    //     uint256 currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
    //     (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
    //     uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
    //                 currentVirtualPrice,
    //                 upper
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, USDC);

    //     // Change virtual price to move it below lower bound.
    //     _adjustVirtualPrice(CRV_WETH_CRV, 1.20e18);
    //     currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
    //     uint256 lower = uint256(datum).mulDivDown(0.99e8, 1e8).changeDecimals(8, 18);

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentBelowLowerBound.selector,
    //                 currentVirtualPrice,
    //                 lower
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, USDC);
    // }

    // // ======================================= AUTOMATION TESTS =======================================
    // function testAutomationLogic() external {
    //     // Set up price router to use mock gas feed.
    //     MockGasFeed gasFeed = new MockGasFeed();
    //     priceRouter.setGasFeed(address(gasFeed));

    //     gasFeed.setAnswer(30e9);

    //     // Add 3Pool to price router.
    //     ICurvePool pool = ICurvePool(daiUsdcUsdtPool);
    //     uint256 oldVirtualPrice = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(oldVirtualPrice),
    //         0,
    //         uint32(1.001e8),
    //         uint32(0.999e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);
    //     (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
    //         abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
    //     );
    //     assertTrue(!upkeepNeeded, "Upkeep should not be needed");
    //     // Increase the virtual price by about 0.10101%
    //     _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.999e18);
    //     vm.warp(block.timestamp + 1 days);
    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed");

    //     // Simulate gas price spike.
    //     gasFeed.setAnswer(300e9);
    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(!upkeepNeeded, "Upkeep should not be needed");

    //     // Gas recovers to a normal level.
    //     gasFeed.setAnswer(30e9);
    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0)));
    //     (uint96 datum, uint64 timeLastUpdated, , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
    //     assertEq(datum, oldVirtualPrice.mulDivDown(1.001e8, 1e8), "Datum should equal old virtual price upper bound.");
    //     assertEq(timeLastUpdated, block.timestamp, "Time last updated should equal current timestamp.");

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(!upkeepNeeded, "Upkeep should not be needed");

    //     // If enough time passes, and gas price becomes low enough, datum may be updated again.
    //     vm.warp(block.timestamp + 1 days);
    //     _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.9995e18);
    //     // With adjusted virtual price new max gas limit should be just over 25 gwei.
    //     gasFeed.setAnswer(25e9);
    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
    //     (datum, timeLastUpdated, , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
    //     assertEq(datum, pool.get_virtual_price().changeDecimals(18, 8), "Datum should equal virtual price.");
    //     assertEq(timeLastUpdated, block.timestamp, "Time last updated should equal current timestamp.");
    // }

    // function testUpkeepPriority() external {
    //     // Add WETH CRV Pool to the price router
    //     ICurveFi pool = ICurveFi(wethCrvPool);
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
    //     uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         0
    //     );
    //     priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), 87.66e8);

    //     // Add 3Crypto to the price router
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
    //     vpBound = PriceRouter.VirtualPriceBound(uint96(1.0248e8), 0, uint32(1.01e8), uint32(0.99e8), 0);
    //     priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 1_136.74e8);

    //     // Add 3Pool to price router.
    //     PriceRouter.ChainlinkDerivativeStorage memory stor;
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
    //     pool = ICurveFi(daiUsdcUsdtPool);
    //     vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
    //     priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

    //     // Add FRAX to price router.
    //     settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
    //     priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

    //     // Add FRAX3CRV to price router.
    //     settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
    //     pool = ICurveFi(frax3CrvPool);
    //     vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
    //     priceRouter.addAsset(CRV_FRAX_3CRV, settings, abi.encode(vpBound), 1.0087e8);

    //     // Advance time to prevent rate limiting.
    //     vm.warp(block.timestamp + 1 days);

    //     // Adjust all Curve Assets virtual prices to make their deltas vary.
    //     _adjustVirtualPrice(CRV_WETH_CRV, 0.95e18);
    //     _adjustVirtualPrice(CRV_3_CRYPTO, 1.1e18);
    //     _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.85e18);
    //     _adjustVirtualPrice(CRV_FRAX_3CRV, 1.30e18);
    //     // Upkeep should prioritize upkeeps in the following order.
    //     // 1) CRV_FRAX_3CRV
    //     // 2) CRV_DAI_USDC_USDT
    //     // 3) CRV_3_CRYPTO
    //     // 4) CRV_WETH_CRV
    //     (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
    //         abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
    //     );
    //     assertTrue(upkeepNeeded, "Upkeep should be needed.");
    //     assertEq(abi.decode(performData, (uint256)), 3, "Upkeep should target index 3.");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed.");
    //     assertEq(abi.decode(performData, (uint256)), 2, "Upkeep should target index 2.");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed.");
    //     assertEq(abi.decode(performData, (uint256)), 1, "Upkeep should target index 1.");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

    //     // Passing in a 5 for the end index should still work.
    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 5)));
    //     assertTrue(upkeepNeeded, "Upkeep should be needed.");
    //     assertEq(abi.decode(performData, (uint256)), 0, "Upkeep should target index 0.");
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     assertTrue(!upkeepNeeded, "Upkeep should not be needed.");
    // }

    // function testRecoveringFromExtremeVirtualPriceMovements() external {
    //     // Add WETH CRV Pool to the price router
    //     ICurveFi pool = ICurveFi(wethCrvPool);
    //     PriceRouter.AssetSettings memory settings;
    //     settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
    //     uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
    //     PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
    //         uint96(vp),
    //         0,
    //         uint32(1.01e8),
    //         uint32(0.99e8),
    //         1 days / 2
    //     );
    //     priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), 87.66e8);

    //     vm.warp(block.timestamp + 1 days / 2);

    //     // Virtual price grows suddenly.
    //     _adjustVirtualPrice(CRV_WETH_CRV, 0.95e18);

    //     // Pricing calls now revert.
    //     uint256 currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
    //     (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
    //     uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
    //                 currentVirtualPrice,
    //                 upper
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

    //     // Keepers adjust the virtual price, but pricing calls still revert.
    //     (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
    //         abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
    //     );
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
    //     (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
    //     upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
    //                 currentVirtualPrice,
    //                 upper
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

    //     // At this point it will still take several days(because of rate limiting), for pricing calls to not revert.
    //     // The owner can do a couple different things.
    //     // Update the rate limit value to something smaller so there is less time between upkeeps.
    //     priceRouter.updateVirtualPriceBound(address(CRV_WETH_CRV), 1.01e8, 0.99e8, 1 days / 8);
    //     // Update the posDelta,a nd negDelta values so the virtual price can be updated more in each upkeep.
    //     // This method is discouraged because the wider the price range is the more susceptible this contract
    //     // is to Curve re-entrancy attacks.
    //     priceRouter.updateVirtualPriceBound(address(CRV_WETH_CRV), 1.02e8, 0.99e8, 1 days / 8);

    //     vm.warp(block.timestamp + 1 days / 8);

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
    //     (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
    //     upper = uint256(datum).mulDivDown(1.02e8, 1e8).changeDecimals(8, 18);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
    //                 currentVirtualPrice,
    //                 upper
    //             )
    //         )
    //     );
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

    //     vm.warp(block.timestamp + 1 days / 8);

    //     (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
    //     vm.prank(automationRegistry);
    //     priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
    //     // Virtual price is now back within logical bounds so pricing operations work as expected.
    //     priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);
    //     (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
    //     upper = uint256(datum).mulDivDown(1.02e8, 1e8).changeDecimals(8, 18);
    // }

    // ======================================= HELPER FUNCTIONS =======================================
    function _adjustVirtualPrice(ERC20 token, uint256 multiplier) internal {
        uint256 targetSupply = token.totalSupply().mulDivDown(multiplier, 1e18);
        stdstore.target(address(token)).sig("totalSupply()").checked_write(targetSupply);
    }
}
