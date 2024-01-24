// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeedForMorphoBlue } from "src/mocks/MockDataFeedForMorphoBlue.sol";
import "test/resources/MainnetStarter.t.sol";
import { MorphoBlueDebtAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueDebtAdaptor.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { MorphoBlueCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueCollateralAdaptor.sol";
import { MorphoBlueSupplyAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import { IMorpho, MarketParams, Id, Market } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";
import "forge-std/console.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { IrmMock } from "src/mocks/IrmMock.sol";

/**
 * @notice Test provision of collateral and borrowing on MorphoBlue Markets.
 * @author 0xEinCodes, crispymangoes
 */
contract MorphoBlueCollateralAndDebtTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;

    MorphoBlueCollateralAdaptor public morphoBlueCollateralAdaptor;
    MorphoBlueDebtAdaptor public morphoBlueDebtAdaptor;
    MorphoBlueSupplyAdaptor public morphoBlueSupplyAdaptor;

    Cellar public cellar;

    uint32 public morphoBlueSupplyWETHPosition = 1_000_001;
    uint32 public morphoBlueCollateralWETHPosition = 1_000_002;
    uint32 public morphoBlueDebtWETHPosition = 1_000_003;
    uint32 public morphoBlueSupplyUSDCPosition = 1_000_004;
    uint32 public morphoBlueCollateralUSDCPosition = 1_000_005;
    uint32 public morphoBlueDebtUSDCPosition = 1_000_006;
    uint32 public morphoBlueSupplyWBTCPosition = 1_000_007;
    uint32 public morphoBlueCollateralWBTCPosition = 1_000_008;
    uint32 public morphoBlueDebtWBTCPosition = 1_000_009;

    IMorpho public morphoBlue = IMorpho(_morphoBlue);
    address public morphoBlueOwner = 0x6ABfd6139c7C3CC270ee2Ce132E309F59cAaF6a2;
    address public DEFAULT_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 public DEFAULT_LLTV = 860000000000000000; // (86% LLTV)

    // Chainlink PriceFeeds
    MockDataFeedForMorphoBlue private mockWethUsd;
    MockDataFeedForMorphoBlue private mockUsdcUsd;
    MockDataFeedForMorphoBlue private mockWbtcUsd;
    MockDataFeedForMorphoBlue private mockDaiUsd;

    uint32 private wethPosition = 1;
    uint32 private usdcPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private daiPosition = 4;

    uint256 initialAssets;
    uint256 minHealthFactor = 1.05e18;

    bool ACCOUNT_FOR_INTEREST = true;

    MarketParams private wethUsdcMarket;
    MarketParams private wbtcUsdcMarket;
    MarketParams private usdcDaiMarket;
    Id private wethUsdcMarketId;
    Id private wbtcUsdcMarketId;
    Id private usdcDaiMarketId;

    address internal SUPPLIER;
    IrmMock internal irm;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18922158;

        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeedForMorphoBlue(USDC_USD_FEED);
        mockWbtcUsd = new MockDataFeedForMorphoBlue(WBTC_USD_FEED);
        mockWethUsd = new MockDataFeedForMorphoBlue(WETH_USD_FEED);
        mockDaiUsd = new MockDataFeedForMorphoBlue(DAI_USD_FEED);

        bytes memory creationCode;
        bytes memory constructorArgs;

        creationCode = type(MorphoBlueCollateralAdaptor).creationCode;
        constructorArgs = abi.encode(address(morphoBlue), minHealthFactor);
        morphoBlueCollateralAdaptor = MorphoBlueCollateralAdaptor(
            deployer.deployContract("Morpho Blue Collateral Adaptor V 0.0", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoBlueDebtAdaptor).creationCode;
        constructorArgs = abi.encode(address(morphoBlue), minHealthFactor);
        morphoBlueDebtAdaptor = MorphoBlueDebtAdaptor(
            deployer.deployContract("Morpho Blue Debt Adaptor V 0.0", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoBlueSupplyAdaptor).creationCode;
        constructorArgs = abi.encode(address(morphoBlue));
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

        // set mock prices for chainlink price feeds, but add in params to adjust the morphoBlue price format needed --> recall from IOracle.sol that the units will be 10 ** (36 - collateralUnits + borrowUnits)

        mockWethUsd.setMockAnswer(2200e8, WETH, USDC);
        mockUsdcUsd.setMockAnswer(1e8, USDC, USDC);
        mockWbtcUsd.setMockAnswer(42000e8, WBTC, USDC);
        mockDaiUsd.setMockAnswer(1e8, DAI, USDC);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(morphoBlueCollateralAdaptor));
        registry.trustAdaptor(address(morphoBlueDebtAdaptor));
        registry.trustAdaptor(address(morphoBlueSupplyAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));

        /// setup morphoBlue test markets; WETH:USDC, WBTC:USDC, USDC:DAI?
        // note - oracle param w/ MarketParams struct is for collateral price

        wethUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WETH),
            oracle: address(mockWethUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        wbtcUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WBTC),
            oracle: address(mockWbtcUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        usdcDaiMarket = MarketParams({
            loanToken: address(DAI),
            collateralToken: address(USDC),
            oracle: address(mockUsdcUsd),
            irm: DEFAULT_IRM,
            lltv: DEFAULT_LLTV
        });

        morphoBlue.createMarket(wethUsdcMarket);
        wethUsdcMarketId = wethUsdcMarket.id();

        morphoBlue.createMarket(wbtcUsdcMarket);
        wbtcUsdcMarketId = wbtcUsdcMarket.id();

        morphoBlue.createMarket(usdcDaiMarket);
        usdcDaiMarketId = usdcDaiMarket.id();

        registry.trustPosition(
            morphoBlueSupplyWETHPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wethUsdcMarket)
        );
        registry.trustPosition(
            morphoBlueCollateralWETHPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(wethUsdcMarket)
        );
        registry.trustPosition(morphoBlueDebtWETHPosition, address(morphoBlueDebtAdaptor), abi.encode(wethUsdcMarket));
        registry.trustPosition(
            morphoBlueSupplyUSDCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(usdcDaiMarket)
        );
        registry.trustPosition(
            morphoBlueCollateralUSDCPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(usdcDaiMarket)
        );
        registry.trustPosition(morphoBlueDebtUSDCPosition, address(morphoBlueDebtAdaptor), abi.encode(usdcDaiMarket));
        registry.trustPosition(
            morphoBlueSupplyWBTCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wbtcUsdcMarket)
        );
        registry.trustPosition(
            morphoBlueCollateralWBTCPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(wbtcUsdcMarket)
        );
        registry.trustPosition(morphoBlueDebtWBTCPosition, address(morphoBlueDebtAdaptor), abi.encode(wbtcUsdcMarket));

        string memory cellarName = "Morpho Blue Collateral & Debt Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(WETH), address(this), initialDeposit);
        WETH.approve(cellarAddress, initialDeposit);

        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            WETH,
            cellarName,
            cellarName,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(morphoBlueSupplyAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoBlueCollateralAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoBlueDebtAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPositionToCatalogue(daiPosition);

        // only add weth adaptor positions for now.
        cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        cellar.addPositionToCatalogue(morphoBlueCollateralWETHPosition);
        cellar.addPositionToCatalogue(morphoBlueDebtWETHPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(true), false);
        cellar.addPosition(2, wbtcPosition, abi.encode(true), false);
        cellar.addPosition(3, morphoBlueSupplyWETHPosition, abi.encode(true), false);
        cellar.addPosition(4, morphoBlueCollateralWETHPosition, abi.encode(0), false);

        cellar.addPosition(0, morphoBlueDebtWETHPosition, abi.encode(0), true);

        WETH.safeApprove(address(cellar), type(uint256).max);
        USDC.safeApprove(address(cellar), type(uint256).max);
        WBTC.safeApprove(address(cellar), type(uint256).max);

        SUPPLIER = makeAddr("Supplier");
    }

    /// MorphoBlueCollateralAdaptor tests

    // test that holding position for adding collateral is being tracked properly and works upon user deposits
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Cellar should have only initial assets, and have supplied the new asset amount as collateral"
        );
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);

        assertEq(newCellarCollateralBalance, assets, "Assets should be collateral provided to Morpho Blue Market.");
    }

    // test adding collateral where holdingPosition is WETH erc20Position
    function testAddCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have all deposited WETH assets"
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Only initialAssets should be within Cellar."
        );

        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);
        assertEq(
            newCellarCollateralBalance,
            assets,
            "Assets (except initialAssets) should be collateral provided to Morpho Blue Market."
        );

        // test balanceOf() of collateralAdaptor
        bytes memory adaptorData = abi.encode(wethUsdcMarket);
        vm.prank(address(cellar));
        uint256 newBalance = morphoBlueCollateralAdaptor.balanceOf(adaptorData);

        assertEq(newBalance, newCellarCollateralBalance, "CollateralAdaptor - balanceOf() additional tests");
    }

    // carry out a total assets test checking that balanceOf works for adaptors.
    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Adaptor totalAssets(): Total assets should equal initialAssets + assets."
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Adaptor totalAssets(): Total assets should not have changed."
        );
    }

    function testRemoveCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(newCellarCollateralBalance, 0);
    }

    function testRemoveSomeCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), (assets / 2) + initialAssets);
        assertApproxEqAbs(newCellarCollateralBalance, assets / 2, 1);
    }

    // test strategist input param for _collateralAmount to be type(uint256).max
    function testRemoveAllCollateralWithTypeUINT256Max(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(newCellarCollateralBalance, 0);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall within collateral adaptor.
    function testBlockExternalReceiver(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ WETH MorphoBlue weth:usdc market
        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            MorphoBlueCollateralAdaptor.withdraw.selector,
            100_000e18,
            maliciousStrategist,
            abi.encode(wethUsdcMarket),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    /// MorphoBlueDebtAdaptor tests

    // test taking loans w/ a morpho blue market
    function testTakingOutLoans(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 1000, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethUsdcMarket);

        vm.prank(address(cellar));
        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);
        assertApproxEqAbs(
            newBalance,
            borrowAmount,
            1,
            "DebtAdaptor - balanceOf() additional tests: Cellar should have debt recorded within Morpho Blue market equal to assets / 2"
        );
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            borrowAmount,
            1,
            "Cellar should have borrow amount equal to assets / 2"
        );
    }

    // test taking loan w/ the wrong pair that we provided collateral to
    function testTakingOutLoanInUntrackedPosition(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // try borrowing from the wrong market that is untracked by cellar
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(usdcDaiMarket, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueHelperLogic.MorphoBlueAdaptors__MarketPositionsMustBeTracked.selector,
                    usdcDaiMarket
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 1000, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan

        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethUsdcMarket);

        // start repayment sequence - NOTE that the repay function in Morpho Blue calls accrue interest within it.
        deal(address(USDC), address(cellar), borrowAmount);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        assertApproxEqAbs(newBalance, 0, 1, "Cellar should have zero debt recorded within Morpho Blue Market");
        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar should have zero debtAsset");
    }

    // ensuring that zero as an input param will revert in various scenarios (due to INCONSISTENT_INPUT error within MorphoBlue (it doesn't allow more than one zero input param) for respective function calls).
    function testRepayingLoansWithZeroInput(uint256 assets) external {
        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        vm.expectRevert();
        cellar.callOnAdaptor(data);

        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 1000, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan

        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Repay the loan
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, 0);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes("inconsistent input"));
        cellar.callOnAdaptor(data);
    }

    function testRepayPartialDebt(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 1000, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan

        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        bytes memory adaptorData = abi.encode(wethUsdcMarket);
        vm.prank(address(cellar));
        uint256 debtBefore = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        // Repay the loan
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, borrowAmount / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        vm.prank(address(cellar));
        uint256 debtNow = morphoBlueDebtAdaptor.balanceOf(adaptorData);
        assertLt(debtNow, debtBefore);
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            borrowAmount / 2,
            1e18,
            "Cellar should have approximately half debtAsset"
        );
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // Try sending out adaptorCalls that has a call with an position that is unregistered within the cellar, should lead to a revert from the adaptor that is trusted.
    function testNestedAdaptorCallLoanInUntrackedPosition(uint256 assets) external {
        // purposely do not trust a debt position with WBTC with the cellar
        cellar.addPositionToCatalogue(morphoBlueCollateralWBTCPosition); // decimals is 8 for wbtc
        cellar.addPosition(5, morphoBlueCollateralWBTCPosition, abi.encode(0), false);
        assets = bound(assets, 0.1e8, 100e8);
        uint256 MBWbtcUsdcBorrowAmount = priceRouter.getValue(WBTC, assets / 2, USDC); // assume wbtcUsdcMarketId corresponds to a wbtc-usdc market on morpho blue

        deal(address(WBTC), address(cellar), assets);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralToMorphoBlue(wbtcUsdcMarket, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowFromMorphoBlue(wbtcUsdcMarket, MBWbtcUsdcBorrowAmount);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(morphoBlueCollateralAdaptor),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCallsSecondAdaptor });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueHelperLogic.MorphoBlueAdaptors__MarketPositionsMustBeTracked.selector,
                    wbtcUsdcMarket
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // have strategist call repay function when no debt owed. Expect revert.
    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes("inconsistent input"));
        cellar.callOnAdaptor(data);
    }

    /// MorphoBlueDebtAdaptor AND MorphoBlueCollateralAdaptor tests

    // Check that multiple morpho blue positions are handled properly
    function testMultipleMorphoBluePositions(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);

        // Add new assets positions to cellar
        cellar.addPositionToCatalogue(morphoBlueCollateralWBTCPosition);
        cellar.addPositionToCatalogue(morphoBlueDebtWBTCPosition);
        cellar.addPosition(5, morphoBlueCollateralWBTCPosition, abi.encode(0), false);
        cellar.addPosition(1, morphoBlueDebtWBTCPosition, abi.encode(0), true);

        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);

        // multiple adaptor calls
        // deposit WETH
        // borrow USDC from weth:usdc morpho blue market
        // deposit WBTC
        // borrow USDC from wbtc:usdc morpho blue market
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MB wethUsdcMarket

        uint256 wbtcAssets = assets.changeDecimals(18, 8);
        deal(address(WBTC), address(cellar), wbtcAssets);
        uint256 wethUSDCToBorrow = priceRouter.getValue(WETH, assets / 2, USDC);
        uint256 wbtcUSDCToBorrow = priceRouter.getValue(WBTC, wbtcAssets / 2, USDC);

        // Supply markets so we can test borrowing from cellar with multiple positions
        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WBTC, assets * 1000, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount * 4);
        USDC.safeApprove(address(morphoBlue), supplyAmount * 4);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        morphoBlue.supply(wbtcUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");

        vm.stopPrank();

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor, MKR already deposited due to cellar holding position
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralToMorphoBlue(wbtcUsdcMarket, wbtcAssets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, wethUSDCToBorrow);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowFromMorphoBlue(wbtcUsdcMarket, wbtcUSDCToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(morphoBlueCollateralAdaptor),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // Check that we have the right amount of USDC borrowed
        assertApproxEqAbs(
            (getMorphoBlueDebtBalance(wethUsdcMarketId, address(cellar))) +
                getMorphoBlueDebtBalance(wbtcUsdcMarketId, address(cellar)),
            wethUSDCToBorrow + wbtcUSDCToBorrow,
            1
        );

        assertApproxEqAbs(USDC.balanceOf(address(cellar)), wethUSDCToBorrow + wbtcUSDCToBorrow, 1);

        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total USDC.
        deal(address(USDC), address(cellar), (wethUSDCToBorrow + wbtcUSDCToBorrow) * 2);

        // Repay the loan in one of the morpho blue markets
        Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, maxAmountToRepay);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        assertApproxEqAbs(
            getMorphoBlueDebtBalance(wethUsdcMarketId, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Morpho Blue Market"
        );

        assertApproxEqAbs(
            getMorphoBlueDebtBalance(wbtcUsdcMarketId, address(cellar)),
            wbtcUSDCToBorrow,
            1,
            "Cellar should still have debt for WBTC Morpho Blue Market"
        );

        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            wethUSDCToBorrow + (2 * wbtcUSDCToBorrow),
            1,
            "Cellar should have paid off debt w/ type(uint256).max but not have paid more than needed."
        );

        deal(address(WETH), address(cellar), 0);

        adaptorCalls2[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, assets);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // Check that we no longer have any WETH in the collateralPosition
        assertEq(WETH.balanceOf(address(cellar)), assets);

        // have user withdraw from cellar
        cellar.withdraw(assets, address(this), address(this));
        assertEq(WETH.balanceOf(address(this)), assets);
    }

    // Test removal of collateral but with taking a loan out and repaying it in full first.
    function testRemoveCollateralWithTypeUINT256MaxAfterRepay(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 10, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethUsdcMarket);

        vm.prank(address(cellar));

        // start repayment sequence - NOTE that the repay function in Morpho Blue calls accrue interest within it.
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total loanToken
        deal(address(USDC), address(cellar), borrowAmount);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethUsdcMarket, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        assertApproxEqAbs(newBalance, 0, 1, "Cellar should have zero debt recorded within Morpho Blue Market");
        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar should have zero debtAsset");

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(newCellarCollateralBalance, 0);
    }

    // test attempting to removeCollateral() when the LTV would be too high as a result
    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 10, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // try to removeCollateral but more than should be allowed
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueCollateralAdaptor.MorphoBlueCollateralAdaptor__HealthFactorTooLow.selector,
                    wethUsdcMarket
                )
            )
        );
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethUsdcMarket, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueCollateralAdaptor.MorphoBlueCollateralAdaptor__HealthFactorTooLow.selector,
                    wethUsdcMarket
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testLTV(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        vm.startPrank(SUPPLIER); // SUPPLIER
        uint256 supplyAmount = priceRouter.getValue(WETH, assets * 10, USDC); // assumes that wethUsdcMarketId is a WETH:USDC market. Correct this if otherwise.

        deal(address(USDC), SUPPLIER, supplyAmount);
        USDC.safeApprove(address(morphoBlue), supplyAmount);
        morphoBlue.supply(wethUsdcMarket, supplyAmount, 0, SUPPLIER, hex"");
        vm.stopPrank();

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets.mulDivDown(1e4, 1.05e4), USDC); // calculate a borrow amount that would make the position unhealthy (health factor wise)

        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes("insufficient collateral"));
        cellar.callOnAdaptor(data);

        // add collateral to be able to borrow amount desired
        deal(address(WETH), address(cellar), 3 * assets);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethUsdcMarket, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(WETH.balanceOf(address(cellar)), assets * 2);

        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethUsdcMarketId, address(cellar)).collateral);
        assertEq(newCellarCollateralBalance, 2 * assets);

        // Try taking out more USDC now
        uint256 moreUSDCToBorrow = priceRouter.getValue(WETH, assets / 2, USDC);
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethUsdcMarket, moreUSDCToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // should transact now
    }

    /// MorphoBlue Collateral and Debt Specific Helpers

    // NOTE - make sure to call `accrueInterest()` beforehand to ensure we get proper debt balance returned
    function getMorphoBlueDebtBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return (((morphoBlue.borrowShares(_id, _user))).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares));
    }

    // NOTE - make sure to call `accrueInterest()` beforehand to ensure we get proper supply balance returned
    function getMorphoBlueSupplyBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        return (
            uint256((morphoBlue.position(_id, _user).supplyShares)).toAssetsUp(
                market.totalSupplyAssets,
                market.totalSupplyShares
            )
        );
    }
}
