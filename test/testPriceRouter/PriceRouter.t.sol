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

import { WstEthExtension } from "src/modules/price-router/Extensions/WstEthExtension.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceRouterTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    event AddAsset(address indexed asset);
    event RemoveAsset(address indexed asset);

    PriceRouter private immutable priceRouter = new PriceRouter();

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

    // ======================================= ASSET TESTS =======================================
    function testAddChainlinkAsset() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            100e18,
            0.0001e18,
            2 days,
            true
        );
        uint256 price = uint256(IChainlinkAggregator(BOND_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(BOND, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        priceRouter.completeEditAsset(BOND, settings, abi.encode(stor), price);

        (uint144 maxPrice, uint80 minPrice, uint24 heartbeat, bool isETH) = priceRouter.getChainlinkDerivativeStorage(
            BOND
        );

        assertTrue(isETH, "BOND data feed should be in ETH");
        assertEq(minPrice, 0.0001e18, "Should set min price");
        assertEq(maxPrice, 100e18, "Should set max price");
        assertEq(heartbeat, 2 days, "Should set heartbeat");
        assertTrue(priceRouter.isSupported(BOND), "Asset should be supported");
    }

    function testMinPriceGreaterThanMaxPrice() external {
        // Make sure adding an asset with an invalid price range fails.
        uint80 minPrice = 2e8;
        uint144 maxPrice = 1e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            maxPrice,
            minPrice,
            2 days,
            false
        );

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(PriceRouter.PriceRouter__MinPriceGreaterThanMaxPrice.selector, minPrice, maxPrice)
        );
        priceRouter.completeEditAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAddInvalidAsset() external {
        PriceRouter.AssetSettings memory settings;
        vm.expectRevert(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidAsset.selector, address(0)));
        priceRouter.addAsset(ERC20(address(0)), settings, abi.encode(0), 0);
    }

    function testAddAssetWithInvalidMinPrice() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 1, 0, false);

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidMinPrice.selector, 1, 1100000)));
        priceRouter.completeEditAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAddAssetWithInvalidMaxPrice() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            999e18,
            0,
            0,
            false
        );

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidMaxPrice.selector, 999e18, 90000000000))
        );
        priceRouter.completeEditAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    /**
     * @notice All pricing operations go through `_getValueInUSD`, so checking for revert in `addAsset` is sufficient.
     */
    function testAssetBelowMinPrice() external {
        // Store price of USDC.
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());

        // Add USDC again, but set a bad minPrice.
        uint80 badMinPrice = 1.1e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            0,
            badMinPrice,
            0,
            false
        );

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__AssetBelowMinPrice.selector,
                    address(USDC),
                    price,
                    badMinPrice
                )
            )
        );
        priceRouter.completeEditAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    /**
     * @notice All pricing operations go through `_getValueInUSD`, so checking for revert in `addAsset` is sufficient.
     */
    function testAssetAboveMaxPrice() external {
        // Store price of USDC.
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());

        // Add USDC again, but set a bad maxPrice.
        uint144 badMaxPrice = 0.9e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            badMaxPrice,
            0,
            0,
            false
        );

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__AssetAboveMaxPrice.selector,
                    address(USDC),
                    price,
                    badMaxPrice
                )
            )
        );
        priceRouter.completeEditAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAssetStalePrice() external {
        // Store timestamp of USDC.
        uint256 timestamp = uint256(IChainlinkAggregator(USDC_USD_FEED).latestTimestamp());
        timestamp = block.timestamp - timestamp;

        // Advance time so that the price becomes stale.
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__StalePrice.selector,
                    address(USDC),
                    timestamp + 1 days,
                    1 days
                )
            )
        );
        priceRouter.getValue(USDC, 1e6, USDC);
    }

    function testETHtoUSDPriceFeedIsChecked() external {
        // Check if querying an asset that needs the ETH to USD price feed, that the feed is checked.
        // Add BOND as an asset.
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            100e18,
            0.0001e18,
            2 days,
            true
        );

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(BOND, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        priceRouter.completeEditAsset(BOND, settings, abi.encode(stor), 4.18e8);

        // Re-add WETH, but shorten the heartbeat.
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        stor = PriceRouter.ChainlinkDerivativeStorage(0, 0.0, 3600, false);

        // Simulate calling startEditAsset.
        editHash = keccak256(abi.encode(WETH, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        priceRouter.completeEditAsset(WETH, settings, abi.encode(stor), 1_775e8);

        uint256 timestamp = uint256(IChainlinkAggregator(WETH_USD_FEED).latestTimestamp());
        timestamp = block.timestamp - timestamp;

        // Advance time forward such that the ETH USD price feed is stale, but the BOND ETH price feed is not.
        vm.warp(block.timestamp + 3600);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__StalePrice.selector,
                    address(WETH),
                    timestamp + 3600,
                    3600
                )
            )
        );
        priceRouter.getValue(BOND, 1e18, USDC);
    }

    // ======================================= EDITING ASSET TESTS =======================================

    // Create a dummy asset that uses this test contract as a mock extension.
    function setupSource(ERC20, bytes memory) external {}

    function getPriceInUSD(ERC20) external view virtual returns (uint256) {
        return 1e8;
    }

    function testEditAsset() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(this));

        // Trying to add an existing asset should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__AssetAlreadyAdded.selector, address(USDC)))
        );
        priceRouter.addAsset(USDC, settings, abi.encode(0), 1e8);

        // Trying to edit some new asset should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__AssetNotAdded.selector, address(777))));
        priceRouter.startEditAsset(ERC20(address(777)), settings, abi.encode(0));

        // USDC is already added, edit it to use this contract as an extension.
        bytes32 editHash = keccak256(abi.encode(USDC, settings, abi.encode(0)));
        priceRouter.startEditAsset(USDC, settings, abi.encode(0));

        assertEq(
            priceRouter.assetEditableTimestamp(editHash),
            block.timestamp + priceRouter.EDIT_ASSET_DELAY(),
            "Asset editable timestamp should be current time plus edit delay."
        );

        // Owner calling `completeEditAsset` with an asset not pending edit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__AssetNotEditable.selector, address(777)))
        );
        priceRouter.completeEditAsset(ERC20(address(777)), settings, abi.encode(0), 1e8);

        // Owner calling `completeEditAsset` early should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__AssetNotEditable.selector, address(USDC)))
        );
        priceRouter.completeEditAsset(USDC, settings, abi.encode(0), 1e8);

        // Once enough time has passed, then `completeEditAsset` will work.
        vm.warp(block.timestamp + priceRouter.EDIT_ASSET_DELAY());
        priceRouter.completeEditAsset(USDC, settings, abi.encode(0), 1e8);

        assertEq(priceRouter.assetEditableTimestamp(editHash), 0, "Asset editable timestamp should be zero.");

        // Trying to cancel an edit asset when no edit is pending reverts.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__AssetNotPendingEdit.selector, address(USDC)))
        );
        priceRouter.cancelEditAsset(USDC, settings, abi.encode(0));

        // If an asset is pending edit, it can be cancelled.
        priceRouter.startEditAsset(USDC, settings, abi.encode(0));

        priceRouter.cancelEditAsset(USDC, settings, abi.encode(0));
    }

    // ======================================= PRICING TESTS =======================================

    function testExchangeRate() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(BOND, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        priceRouter.completeEditAsset(BOND, settings, abi.encode(stor), 4.18e8);
        uint256 exchangeRate;

        // Test exchange rates work when quote is same as base.
        exchangeRate = priceRouter.getExchangeRate(USDC, USDC);
        assertEq(exchangeRate, 1e6, "USDC -> USDC Exchange Rate Should be 1e6");

        exchangeRate = priceRouter.getExchangeRate(DAI, DAI);
        assertEq(exchangeRate, 1e18, "DAI -> DAI Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WETH, WETH);
        assertEq(exchangeRate, 1e18, "WETH -> WETH Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WBTC, WBTC);
        assertEq(exchangeRate, 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");

        exchangeRate = priceRouter.getExchangeRate(BOND, BOND); // Weird asset with an ETH price but no USD price.
        assertEq(exchangeRate, 1e18, "BOND -> BOND Exchange Rate Should be 1e18");

        // // Test exchange rates.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint256[] memory amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(DAI, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "DAI -> USDC Exchange Rate Should be 1 +- 1% USDC");

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, WBTC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> WBTC Exchange Rate Should be 0.5ish +- 1% WBTC");

        path[0] = address(WETH);
        path[1] = address(USDC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> USDC Exchange Rate Failure");

        path[0] = address(USDC);
        path[1] = address(BOND);
        amounts = uniV2Router.getAmountsOut(1e6, path);

        exchangeRate = priceRouter.getExchangeRate(USDC, BOND);
        assertApproxEqRel(exchangeRate, amounts[1], 0.02e18, "USDC -> BOND Exchange Rate Failure");

        ERC20[] memory baseAssets = new ERC20[](5);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = WETH;
        baseAssets[3] = WBTC;
        baseAssets[4] = BOND;

        uint256[] memory exchangeRates = priceRouter.getExchangeRates(baseAssets, WBTC);

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        assertApproxEqRel(exchangeRates[2], amounts[1], 1e16, "WBTC exchangeRates failed against WETH");

        assertEq(exchangeRates[3], 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");
    }

    function testGetValue(uint256 assets0, uint256 assets1, uint256 assets2) external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        // Simulate calling startEditAsset.
        bytes32 editHash = keccak256(abi.encode(BOND, settings, abi.encode(stor)));
        stdstore
            .target(address(priceRouter))
            .sig(priceRouter.assetEditableTimestamp.selector)
            .with_key(editHash)
            .checked_write(uint256(1));

        priceRouter.completeEditAsset(BOND, settings, abi.encode(stor), 4.18e8);

        // Check if `getValues` reverts if assets array and amount array lengths differ
        ERC20[] memory baseAssets = new ERC20[](3);
        uint256[] memory amounts = new uint256[](2);
        vm.expectRevert(PriceRouter.PriceRouter__LengthMismatch.selector);
        priceRouter.getValues(baseAssets, amounts, USDC);

        assets0 = bound(assets0, 1e6, type(uint72).max);
        assets1 = bound(assets1, 1e18, type(uint112).max);
        assets2 = bound(assets2, 1e8, type(uint48).max);

        baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = BOND;
        baseAssets[2] = WBTC;

        amounts = new uint256[](3);
        amounts[0] = assets0;
        amounts[1] = assets1;
        amounts[2] = assets2;

        uint256 totalValue = priceRouter.getValues(baseAssets, amounts, USDC);

        // Find the value using uniswap.

        uint256 sum = assets0; // Since the first one is USDC, no conversion is needed.

        address[] memory path = new address[](2);
        path[0] = address(BOND);
        path[1] = address(USDC);
        uint256[] memory amountsOut = uniV2Router.getAmountsOut(1e18, path);
        sum += (amountsOut[1] * assets1) / 1e18;

        path[0] = address(WBTC);
        path[1] = address(USDC);
        amountsOut = uniV2Router.getAmountsOut(1e4, path);
        sum += (amountsOut[1] * assets2) / 1e4;

        // Most tests use a 1% price difference between Chainlink and Uniswap, but WBTC value
        // derived from Uniswap is significantly off from historical values, while the value
        // calculated by the price router is much more accurate.
        assertApproxEqRel(
            totalValue,
            sum,
            0.05e18,
            "Total Value of USDC, BOND, and WBTC outside of 10% envelope with UniV2"
        );
    }

    function testUnsupportedAsset() external {
        ERC20 LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

        // Check that price router `getValue` reverts if the base asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValue(LINK, 0, WETH);

        // Check that price router `getValue` reverts if the quote asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValue(WETH, 0, LINK);

        ERC20[] memory assets = new ERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        // Check that price router `getValues` reverts if the base asset is not supported.
        assets[0] = LINK;
        amounts[0] = 1; // If amount is zero, getValues skips pricing the asset.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValues(assets, amounts, WETH);

        // Check that price router `getValues` reverts if the quote asset is not supported.
        assets[0] = WETH;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValues(assets, amounts, LINK);

        // Check that price router `getExchange` reverts if the base asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRate(LINK, WETH);

        // Check that price router `getExchangeRate` reverts if the quote asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRate(WETH, LINK);

        // Check that price router `getExchangeRates` reverts if the base asset is not supported.
        assets[0] = LINK;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRates(assets, WETH);

        // Check that price router `getExchangeRates` reverts if the quote asset is not supported.
        assets[0] = WETH;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRates(assets, LINK);
    }

    // ======================================= AUDIT ISSUES =======================================
    // M-2
    function testNumericError() external {
        uint256 amount = 100_000_000e18;
        deal(address(WETH), address(this), amount);
        uint256 inputAmountWorth = priceRouter.getValue(WETH, amount, USDC);

        ERC20[] memory baseAssets = new ERC20[](1);
        uint256[] memory amounts2 = new uint256[](1);

        baseAssets[0] = WETH;
        amounts2[0] = amount;

        uint256 totalValue = priceRouter.getValues(baseAssets, amounts2, USDC);

        assertEq(totalValue, inputAmountWorth, "Values should be equal.");
    }

    // ======================================= HELPER FUNCTIONS =======================================
    function _adjustVirtualPrice(ERC20 token, uint256 multiplier) internal {
        uint256 targetSupply = token.totalSupply().mulDivDown(multiplier, 1e18);
        stdstore.target(address(token)).sig("totalSupply()").checked_write(targetSupply);
    }
}
