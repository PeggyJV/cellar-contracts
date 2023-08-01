// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract PriceRouterTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;

    event AddAsset(address indexed asset);
    event RemoveAsset(address indexed asset);

    IUniswapV2Router private uniswapV2Router = IUniswapV2Router(uniV2Router);

    // UniV3 WETH/RPL Pool
    address private WETH_RPL_03_POOL = 0xe42318eA3b998e8355a3Da364EB9D48eC725Eb45;
    address private WETH_USDC_005_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        // Set Registry 0 id to be the real gravity bridge.
        registry.setAddress(0, gravityBridgeAddress);

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

    function testAddingATwapAsset() external {
        UniswapV3Pool pool = UniswapV3Pool(WETH_RPL_03_POOL);

        pool.increaseObservationCardinalityNext(900);
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        stor.inETH = true;

        // Try adding a twap asset with the wrong pool.
        settings = PriceRouter.AssetSettings(TWAP_DERIVATIVE, WETH_USDC_005_POOL);
        PriceRouter.TwapDerivativeStorage memory twapStor = PriceRouter.TwapDerivativeStorage({
            secondsAgo: 900,
            baseDecimals: 18,
            quoteDecimals: 18,
            quoteToken: WETH
        });
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TwapAssetNotInPool.selector)));
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 41.86e8);

        // Now fix the pool but use a very small TWAP period.
        settings = PriceRouter.AssetSettings(TWAP_DERIVATIVE, WETH_RPL_03_POOL);
        twapStor.secondsAgo = 300;
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__SecondsAgoDoesNotMeetMinimum.selector)));
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 41.86e8);

        // Fix seconds ago to add the asset.
        twapStor.secondsAgo = 900;

        // Provide a bad answer.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__BadAnswer.selector, 4186877370, 35.86e8))
        );
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 35.86e8);

        // Correct the answer.
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 41.86e8);
    }

    // ======================================= TRANSITIONING OWNER TESTS =======================================

    function testTransitioningOwner() external {
        address newOwner = vm.addr(777);
        // Current owner has been misbehaving, so governance wants to kick them out.

        // Governance accidentally passes in zero address for new owner.
        vm.startPrank(gravityBridgeAddress);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__NewOwnerCanNotBeZero.selector)));
        priceRouter.transitionOwner(address(0));
        vm.stopPrank();

        // Governance actually uses the right address.
        vm.prank(gravityBridgeAddress);
        priceRouter.transitionOwner(newOwner);

        // Old owner tries to call onlyOwner functions.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TransitionPending.selector)));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        // New owner tries claiming ownership before transition period is over.
        vm.startPrank(newOwner);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TransitionPending.selector)));
        priceRouter.completeTransition();
        vm.stopPrank();

        vm.warp(block.timestamp + priceRouter.TRANSITION_PERIOD());

        vm.prank(newOwner);
        priceRouter.completeTransition();

        assertEq(priceRouter.owner(), newOwner, "PriceRouter should be owned by new owner.");

        // New owner renounces ownership.
        vm.prank(newOwner);
        priceRouter.renounceOwnership();

        address doug = vm.addr(13);
        // Governance decides to recover ownership and transfer it to doug.
        vm.prank(gravityBridgeAddress);
        priceRouter.transitionOwner(doug);

        // Half way through transition governance learns doug is evil, so they cancel the transition.
        vm.warp(block.timestamp + priceRouter.TRANSITION_PERIOD() / 2);
        vm.prank(gravityBridgeAddress);
        priceRouter.cancelTransition();

        // doug still tries to claim ownership.
        vm.warp(block.timestamp + priceRouter.TRANSITION_PERIOD() / 2);
        vm.startPrank(doug);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TransitionNotPending.selector)));
        priceRouter.completeTransition();
        vm.stopPrank();

        // Governance accidentally calls cancel transition again, but call reverts.
        vm.startPrank(gravityBridgeAddress);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TransitionNotPending.selector)));
        priceRouter.cancelTransition();
        vm.stopPrank();

        // Governance finds the best owner and starts the process.
        address bestOwner = vm.addr(7777);
        vm.prank(gravityBridgeAddress);
        priceRouter.transitionOwner(bestOwner);

        // New owner waits an extra week.
        vm.warp(block.timestamp + 2 * priceRouter.TRANSITION_PERIOD());

        vm.prank(bestOwner);
        priceRouter.completeTransition();

        assertEq(priceRouter.owner(), bestOwner, "PriceRouter should be owned by best owner.");

        // Governance starts another ownership transfer back to doug.
        vm.prank(gravityBridgeAddress);
        priceRouter.transitionOwner(doug);

        vm.warp(block.timestamp + 2 * priceRouter.TRANSITION_PERIOD());

        // Doug still has not completed the transfer, so Governance decides to cancel it.
        vm.prank(gravityBridgeAddress);
        priceRouter.cancelTransition();

        // Doug tries completing it.
        vm.startPrank(doug);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__TransitionNotPending.selector)));
        priceRouter.completeTransition();
        vm.stopPrank();
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

        vm.warp(block.timestamp + priceRouter.EDIT_ASSET_DELAY() / 2);

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

        UniswapV3Pool pool = UniswapV3Pool(WETH_RPL_03_POOL);

        pool.increaseObservationCardinalityNext(900);
        settings = PriceRouter.AssetSettings(TWAP_DERIVATIVE, WETH_RPL_03_POOL);
        PriceRouter.TwapDerivativeStorage memory twapStor = PriceRouter.TwapDerivativeStorage({
            secondsAgo: 900,
            baseDecimals: 18,
            quoteDecimals: 18,
            quoteToken: WETH
        });
        priceRouter.addAsset(RPL, settings, abi.encode(twapStor), 41.86e8);

        // Test exchange rates work when quote is same as base.
        exchangeRate = priceRouter.getExchangeRate(USDC, USDC);
        assertEq(exchangeRate, 1e6, "USDC -> USDC Exchange Rate Should be 1e6");

        exchangeRate = priceRouter.getExchangeRate(RPL, RPL);
        assertEq(exchangeRate, 1e18, "RPL -> RPL Exchange Rate Should be 1e18");

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
        uint256[] memory amounts = uniswapV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(DAI, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "DAI -> USDC Exchange Rate Should be 1 +- 1% USDC");

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniswapV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, WBTC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> WBTC Exchange Rate Should be 0.5ish +- 1% WBTC");

        path[0] = address(WETH);
        path[1] = address(USDC);
        amounts = uniswapV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> USDC Exchange Rate Failure");

        path[0] = address(USDC);
        path[1] = address(BOND);
        amounts = uniswapV2Router.getAmountsOut(1e6, path);

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
        amounts = uniswapV2Router.getAmountsOut(1e18, path);

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
        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(1e18, path);
        sum += (amountsOut[1] * assets1) / 1e18;

        path[0] = address(WBTC);
        path[1] = address(USDC);
        amountsOut = uniswapV2Router.getAmountsOut(1e4, path);
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
}
