// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { MorphoBlueSupplyAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import { IMorpho, MarketParams, Id, Market } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";

/**
 * TODO - setup of actual morpho deployment, or use of mainnet deployments are TBD for this and other related test files (debt and collateral adaptors)
 * TODO - make it so that the test setup has MorphoBlue markets lending out USDC. So that means I'll have to replace the `usdcDaiMarketId` with something else, and add pricing for the other asset (actually probs not needed but will be needed in collateral and debt adaptor tests). This reformat will be needed in the collateral and debt adaptor tests too). tldr - for all supply tests, we are supplying USDC. We need to reformat accordingly. Things to rename accordingly include (but aren't limited to): marketIds --> rename so they reflect both assets in the market (ie. wethUsdcMarketId instead of just wethUsdcMarketId), Positions should reflect both assets involved as well, we'll need to make sure the markets obviously reflect the assets we plan for as well... so need to deploy new markets (See tests within morpho blue repo for this)
 * TODO - INPUT PRODUCTION SMART CONTRACT ADDRESSES FOR MORPHOBLUE AND DEFAULT_IRM WHEN THEY ARE READY.
 *
 */
contract MorphoBlueSupplyAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;
    using MarketParamsLib for MarketParams;

    MorphoBlueSupplyAdaptor public morphoBlueSupplyAdaptor;
    // TODO - do we need mocks adaptors?

    Cellar private cellar;

    // Chainlink PriceFeeds
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockWbtcUsd;
    MockDataFeed private mockDaiUsd;

    uint32 private wethPosition = 1;
    uint32 private usdcPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private daiPosition = 4;

    uint32 public morphoBlueSupplyWETHPosition = 1_000_001;
    uint32 public morphoBlueSupplyUSDCPosition = 1_000_002;
    uint32 public morphoBlueSupplyWBTCPosition = 1_000_003;
    uint32 public morphoBlueSupplyUSDCPosition2 = 1_000_004;

    bool ACCOUNT_FOR_INTEREST = true;

    //============================================ VIP ===========================================

    // TODO - INPUT PRODUCTION SMART CONTRACT ADDRESSES FOR MORPHOBLUE AND DEFAULT_IRM WHEN THEY ARE READY.
    IMorpho public morphoBlue = IMorpho();
    address DEFAULT_IRM = address(0);
    uint256 DEFAULT_LLTV = 860000000000000000; // (86% LLTV)

    MarketParams private wethUsdcMarket;
    MarketParams private wbtcUsdcMarket;
    MarketParams private usdcDaiMarket;
    Id private wethUsdcMarketId;
    Id private wbtcUsdcMarketId;
    Id private usdcDaiMarketId;
    Id private usdcDaiMarketId2;
    Id private UNTRUSTED_mbMarketFakeId = 1_009_000;

    uint256 initialAssets;
    uint256 initialLend;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18922158;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        mockWbtcUsd = new MockDataFeed(WBTC_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockDaiUsd = new MockDataFeed(DAI_USD_FEED);

        bytes memory creationCode;
        bytes memory constructorArgs;

        creationCode = type(MorphoBlueSupplyAdaptor).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(morphoBlue));
        morphoBlueSupplyAdaptor = MorphoBlueSupplyAdaptor(
            deployer.deployContract("Morpho Blue Supply Adaptor V 0.0", creationCode, constructorArgs, 0)
        );
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(mockUsdcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(mockWbtcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWbtcUsd));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(mockDaiUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockDaiUsd));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(morphoBlueSupplyAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));

        /// setup morphoBlue test markets; WETH:USDC, WBTC:USDC, USDC:DAI?

        // note - oracle param w/ MarketParams struct is for collateral price
        // setup morphoBlue WETH:USDC market

        wethUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WETH),
            oracle: address(mockWethUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        // setup morphoBlue WBTC:USDC market
        wbtcUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WBTC),
            oracle: address(mockWbtcUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        // setup morphoBlue USDC:DAI market
        usdcDaiMarket = MarketParams({
            loanToken: address(DAI),
            collateralToken: address(USDC),
            oracle: address(mockUsdcUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        // TODO - add a second usdcDai market

        morphoBlue.createMarket(wethUsdcMarket);
        wethUsdcMarketId = wethUsdcMarket.id();

        morphoBlue.createMarket(wbtcUsdcMarket);
        wbtcUsdcMarketId = wbtcUsdcMarket.id();

        morphoBlue.createMarket(usdcDaiMarket);
        usdcDaiMarketId = usdcDaiMarket.id();

        registry.trustPosition(
            morphoBlueSupplyWETHPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wethUsdcMarketId)
        );
        registry.trustPosition(
            morphoBlueSupplyUSDCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(usdcDaiMarketId)
        );
        registry.trustPosition(
            morphoBlueSupplyWBTCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wbtcUsdcMarketId)
        );
        registry.trustPosition(
            morphoBlueSupplyUSDCPosition2,
            address(morphoBlueSupplyAdaptor),
            abi.encode(usdcDaiMarketId2)
        );

        string memory cellarName = "Morpho Blue Supply Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        WETH.approve(cellarAddress, initialDeposit);

        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(USDC),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(morphoBlueSupplyAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wbtcPosition);

        // only add weth positions for now.
        cellar.addPositionToCatalogue(morphoBlueSupplyUSDCPosition);

        cellar.addPosition(1, wethPosition, abi.encode(0), false);
        cellar.addPosition(2, wbtcPosition, abi.encode(0), false);
        cellar.addPosition(3, morphoBlueSupplyUSDCPosition, abi.encode(0), false);

        cellar.setHoldingPosition(morphoBlueSupplyUSDCPosition);

        WETH.safeApprove(address(cellar), type(uint256).max);
        USDC.safeApprove(address(cellar), type(uint256).max);
        WBTC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend USDC on Morpho Blue. Use the initial deposit that is in the cellar to begin with.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarketId, initialDeposit);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        initialLend = _userSupplyBalance(usdcDaiMarketId);
        assertEq(
            initialLend,
            initialAssets,
            "Should be equal as the test setup includes lending initialDeposit of USDC into Morpho Blue"
        ); // TODO - maybe move this out of the setup.
    }

    // Set up has supply usdc position fully trusted (cellar and registry), weth and wbtc supply positions trusted w/ registry. mbsupplyusdc position is holding position.

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.01e8, 100_000_000e8);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // TODO add asserts
    }

    // function testWithdraw(uint256 assets) external {
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     cellar.withdraw(assets - 2, address(this), address(this));

    //     // TODO add asserts
    // }

    // function testTotalAssets(uint256 assets) external {
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));
    //     assertApproxEqAbs(
    //         cellar.totalAssets(),
    //         assets + initialAssets,
    //         2,
    //         "Total assets should equal assets deposited."
    //     );
    // }

    // function testLendingUSDC(uint256 assets) external {
    //     cellar.setHoldingPosition(usdcPosition); // set holding position back to erc20Position

    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Strategist rebalances to lend USDC.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     // Lend USDC on Morpho Blue.
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarketId, assets);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     uint256 newSupplyBalance = _userSupplyBalance(usdcDaiMarketId, address(cellar));
    //     // check supply share balance for cellar has increased.
    //     assertTrue(newSupplyBalance, initialLend, "Cellar should have supplied more USDC to MB market");
    //     assertApproxEqAbs(
    //         newSupplyBalance,
    //         assets + initialAssets,
    //         2,
    //         "Rebalance should have lent all USDC on Morpho Blue."
    //     );
    // }

    // // w/ holdingPosition as morphoBlueSupplyUSDC, we make sure that strategists can lend to the holding position outright. ie.) some airdropped assets were swapped to USDC to use in morpho blue.
    // function testStrategistLendWithHoldingPosition(uint256 assets) external {
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(cellar), assets);

    //     // Strategist rebalances to lend USDC.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     // Lend USDC on Morpho Blue.
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarketId, assets);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     uint256 newSupplyBalance = _userSupplyBalance(usdcDaiMarketId, address(cellar));
    //     // check supply share balance for cellar has increased.
    //     assertTrue(newSupplyBalance == initialLend, "Cellar should have supplied more USDC to MB market");
    //     assertApproxEqAbs(
    //         newSupplyBalance,
    //         assets + initialAssets,
    //         2,
    //         "Rebalance should have lent all USDC on Morpho Blue."
    //     );
    // }

    // function testWithdrawingUSDC(uint256 assets) external {
    //     // Have user deposit into cellar.
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Strategist rebalances to withdraw.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarketId, type(uint256).max);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     assertApproxEqAbs(
    //         USDC.balanceOf(address(cellar)),
    //         assets + initialAssets,
    //         2,
    //         "Cellar USDC should have been withdraw from Morpho Blue Market."
    //     );
    // }

    // // lend assets into holdingPosition (morphoSupplyUSDCPosition, and then withdraw the USDC from it and lend it into a new market, usdcDaiMarketId2 (a different morpho blue usdc market)
    // function testRebalancingBetweenPairs(uint256 assets) external {
    //     // Add another Morpho Blue Market to cellar
    //     cellar.addPositionToCatalogue(morphoBlueSupplyUSDCPosition2);
    //     cellar.addPosition(4, morphoBlueSupplyUSDCPosition2, abi.encode(0), false);

    //     // Have user deposit into cellar.
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Strategist rebalances to withdraw, and lend in a different pair.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
    //     // Withdraw USDC from MB market
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarketId, type(uint256).max);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarketId2, type(uint256).max);
    //         data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     uint256 newSupplyBalance = _userSupplyBalance(usdcDaiMarketId2, address(cellar));

    //     assertTrue(newSupplyBalance > 0, "Cellar should have supplied more USDC to MB market");
    //     assertApproxEqAbs(
    //         newSupplyBalance,
    //         assets + initialAssets,
    //         2,
    //         "Rebalance should have lent all USDC on new Morpho Blue USDC marketId2."
    //     );

    //     ///

    //     // Withdraw half the assets
    //     data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarketId2, assets / 2);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     assertEq(
    //         USDC.balanceOf(address(cellar)),
    //         assets / 2,
    //         "Should have withdrawn half the assets from MB Market usdcDaiMarketId2."
    //     );

    //     // check that withdrawn amount makes sense
    //     newSupplyBalance = _userSupplyBalance(usdcDaiMarketId2, address(cellar)); // TODO - could probably get rid of this assertion since we'll have dedicated withdraw tests.
    //     assertApproxEqAbs(
    //         newSupplyBalance,
    //         assets + initialAssets - (assets / 2),
    //         2,
    //         "Rebalance should have led to some assets withdrawn from MB Market usdcDaiMarketId2."
    //     );
    // }

    // //
    // function testUsingMarketNotSetupAsPosition(uint256 assets) external {
    //     cellar.setHoldingPosition(usdcPosition); // set holding position back to erc20Position

    //     // Have user deposit into cellar.
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Strategist rebalances to lend USDC but with an untrusted market.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(UNTRUSTED_mbMarketFakeId, assets);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 MorphoBlueSupplyAdaptor.MorphoBlueSupplyAdaptor__MarketPositionsMustBeTracked.selector,
    //                 (UNTRUSTED_mbMarketFakeId)
    //             )
    //         )
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    // // Check that loanToken in multiple different pairs is correctly accounted for in totalAssets().
    // function testMultiplePositionsTotalAssets(uint256 assets) external {
    //     // Have user deposit into cellar
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     uint256 dividedAssetPerMultiPair = assets / 3; // amount of loanToken (where we've made it the same one for these tests) to distribute between different morpho blue markets
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Test that users can withdraw from multiple pairs at once.
    //     _setupMultiplePositions(dividedAssetPerMultiPair);

    //     assertApproxEqAbs(
    //         assets + initialAssets,
    //         cellar.totalAssets(),
    //         10,
    //         "Total assets should have been lent out and are accounted for via MorphoBlueSupplyAdaptor positions."
    //     );
    // }

    // // Check that user able to withdraw from multiple lending positions outright
    // function testMultiplePositionsUserWithdraw(uint256 assets) external {
    //     // Have user deposit into cellar
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     uint256 dividedAssetPerMultiPair = assets / 3; // amount of loanToken to distribute between different markets
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // Test that users can withdraw from multiple pairs at once.
    //     _setupMultiplePositions(dividedAssetPerMultiPair);

    //     deal(address(USDC), address(this), 0);
    //     uint256 toWithdraw = cellar.maxWithdraw(address(this));
    //     cellar.withdraw(toWithdraw, address(this), address(this));

    //     assertApproxEqAbs(
    //         USDC.balanceOf(address(this)),
    //         toWithdraw,
    //         10,
    //         "User should have gotten all their USDC (minus some dust)"
    //     );
    // }

    // // TODO - this depends on having withdrawableFrom() use periphery, OR have accrueInterest() called before calling totalWithdrawableFrom() within a cellar to include accrued interest. For now it is written roughly but it needs to know if it goes with periiphery or accrueInterest() setup.
    // function testWithdrawableFrom() external {
    //     cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(0), false);

    //     // Strategist rebalances to withdraw USDC, and lend in a different pair.
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
    //     // Withdraw USDC from Morpho Blue.
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarketId, type(uint256).max);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarketId, type(uint256).max);
    //         data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }
    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);

    //     // Make cellar deposits lend USDC into WETH Pair by default
    //     cellar.setHoldingPosition(morphoBlueSupplyWETHPosition);

    //     uint256 assets = 10_000e8;
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     address whaleBorrower = vm.addr(777);

    //     // Figure out how much the whale must borrow to borrow all the loanToken.
    //     uint256 totalLoanTokenSupplied = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
    //     uint256 totalLoanTokenBorrowed = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);

    //     uint256 assetsToBorrow = totalLoanTokenSupplied > totalLoanTokenBorrowed
    //         ? totalLoanTokenSupplied - totalLoanTokenBorrowed
    //         : 0;
    //     // Supply 2x the value we are trying to borrow in weth market collateral (WETH)
    //     uint256 collateralToProvide = priceRouter.getValue(USDC, 2 * assetsToBorrow, WETH);

    //     deal(address(WETH), whaleBorrower, collateralToProvide);

    //     vm.startPrank(whaleBorrower);
    //     WETH.approve(address(morphoBlue), collateralToProvide);

    //     MarketParams memory market = morphoBlue.idToMarketParams(wethUsdcMarketId);

    //     morphoBlue.supplyCollateral(market, collateralToProvide, whaleBorrower, hex"");

    //     // now borrow
    //     morphoBlue.borrow(market, assetsToBorrow, 0, whaleBorrower, whaleBorrower);
    //     vm.stopPrank();

    //     uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();

    //     assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");

    //     // Whale repays half of their debt.
    //     uint256 sharesToRepay = (morphoBlue.position(wethUsdcMarketId, whaleBorrower).borrowShares) / 2;

    //     vm.startPrank(whaleBorrower);
    //     USDC.approve(address(morphoBlue), assetsToBorrow);
    //     morphoBlue.repay(market, 0, sharesToRepay, whaleBorrower, hex"");
    //     vm.stopPrank();

    //     uint256 totalLoanTokenSupplied2 = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
    //     uint256 totalLoanTokenBorrowed2 = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);
    //     uint256 liquidLoanToken2 = totalLoanTokenSupplied2 - totalLoanTokenBorrowed2;
    //     assetsWithdrawable = cellar.totalAssetsWithdrawable();

    //     assertEq(assetsWithdrawable, liquidLoanToken2, "Should be able to withdraw liquid loanToken.");

    //     // Have user withdraw the loanToken.
    //     deal(address(USDC), address(this), 0);
    //     cellar.withdraw(liquidLoanToken2, address(this), address(this));
    //     assertEq(USDC.balanceOf(address(this)), liquidLoanToken2, "User should have received liquid loanToken.");
    // }

    // function testAccrueInterest(uint256 assets) external {
    //     assets = bound(assets, 0.01e8, 100_000_000e8);
    //     deal(address(USDC), address(this), assets);
    //     cellar.deposit(assets, address(this));
    //     uint256 balance1 = (_userSupplyBalance(usdcDaiMarketId1, address(cellar)));

    //     vm.warp(block.timestamp + (10 days));

    //     // Strategist rebalances to accrue interest in markets
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     {
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToAccrueInterestToMorphoBlue(usdcDaiMarketId);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
    //     }

    //     // Perform callOnAdaptor.
    //     cellar.callOnAdaptor(data);
    //     uint256 balance2 = (_userSupplyBalance(usdcDaiMarketId1, address(cellar)));

    //     assertGt(balance2, balance1, "Supplied loanAsset into MorphoBlue should have accrued interest.");
    // }

    // // ========================================= HELPER FUNCTIONS =========================================

    // setup multiple lending positions
    function _setupMultiplePositions(uint256 dividedAssetPerMultiPair) internal {
        // add numerous USDC markets atop of holdingPosition
        cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(0), false);
        cellar.addPosition(5, morphoBlueSupplyWBTCPosition, abi.encode(0), false);

        // Strategist rebalances to withdraw set amount of USDC, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Withdraw 2/3 of cellar USDC from one MB market, then redistribute to other MB markets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarketId, dividedAssetPerMultiPair * 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarketId, dividedAssetPerMultiPair);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wbtcUsdcMarketId, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    /**
     * @dev helper function that returns actual supply position amount for caller according to MB market accounting. This is alternative to using the MB periphery libraries that simulate accrued interest balances.
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers
     */
    function _userSupplyBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return (
            uint256((morphoBlue.position(_id, _user).supplyShares)).toAssetsUp(
                market.totalSupplyAssets,
                market.totalSupplyShares
            )
        );
    }
}
