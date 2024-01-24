// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { MockDataFeedForMorphoBlue } from "src/mocks/MockDataFeedForMorphoBlue.sol";
import { MorphoBlueSupplyAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import { IMorpho, MarketParams, Id, Market } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { IrmMock } from "src/mocks/IrmMock.sol";
import "test/resources/MainnetStarter.t.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";

contract MorphoBlueSupplyAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;

    MorphoBlueSupplyAdaptor public morphoBlueSupplyAdaptor;

    Cellar private cellar;

    // Chainlink PriceFeeds
    MockDataFeedForMorphoBlue private mockWethUsd;
    MockDataFeedForMorphoBlue private mockUsdcUsd;
    MockDataFeedForMorphoBlue private mockWbtcUsd;
    MockDataFeedForMorphoBlue private mockDaiUsd;

    uint32 private wethPosition = 1;
    uint32 private usdcPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private daiPosition = 4;

    uint32 public morphoBlueSupplyWETHPosition = 1_000_001;
    uint32 public morphoBlueSupplyUSDCPosition = 1_000_002;
    uint32 public morphoBlueSupplyWBTCPosition = 1_000_003;

    address private whaleBorrower = vm.addr(777);

    IMorpho public morphoBlue = IMorpho(_morphoBlue);
    address public morphoBlueOwner = 0x6ABfd6139c7C3CC270ee2Ce132E309F59cAaF6a2;
    address public DEFAULT_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 public DEFAULT_LLTV = 860000000000000000; // (86% LLTV)

    MarketParams private wethUsdcMarket;
    MarketParams private wbtcUsdcMarket;
    MarketParams private usdcDaiMarket;
    MarketParams private UNTRUSTED_mbFakeMarket;
    Id private wethUsdcMarketId;
    Id private wbtcUsdcMarketId;
    Id private usdcDaiMarketId;
    // Id private UNTRUSTED_mbFakeMarket = Id.wrap(bytes32(abi.encode(1_000_009)));

    uint256 initialAssets;
    uint256 initialLend;
    IrmMock internal irm;
    address public FEE_RECIPIENT = address(9000);

    function setUp() external {
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

        // set mock prices for chainlink price feeds, but add in params to adjust the morphoBlue price format needed --> recall from IOracle.sol (from Morpho Blue repo) that the units will be 10 ** (36 - collateralUnits + borrowUnits).

        mockWethUsd.setMockAnswer(2200e8, WETH, USDC);
        mockUsdcUsd.setMockAnswer(1e8, USDC, USDC);
        mockWbtcUsd.setMockAnswer(42000e8, WBTC, USDC);
        mockDaiUsd.setMockAnswer(1e8, DAI, USDC);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(morphoBlueSupplyAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));

        // We will work with a mock IRM similar to tests within Morpho Blue repo.

        irm = new IrmMock();

        vm.startPrank(morphoBlueOwner);
        morphoBlue.enableIrm(address(irm));
        morphoBlue.setFeeRecipient(FEE_RECIPIENT);
        vm.stopPrank();

        wethUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WETH),
            oracle: address(mockWethUsd),
            irm: address(irm),
            lltv: DEFAULT_LLTV
        });

        // setup morphoBlue WBTC:USDC market
        wbtcUsdcMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(WBTC),
            oracle: address(mockWbtcUsd),
            irm: address(irm),
            lltv: DEFAULT_LLTV
        });

        // setup morphoBlue USDC:DAI market
        usdcDaiMarket = MarketParams({
            loanToken: address(USDC),
            collateralToken: address(DAI),
            oracle: address(mockUsdcUsd),
            irm: address(irm),
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
            morphoBlueSupplyUSDCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(usdcDaiMarket)
        );
        registry.trustPosition(
            morphoBlueSupplyWBTCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wbtcUsdcMarket)
        );

        string memory cellarName = "Morpho Blue Supply Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(morphoBlueSupplyAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wbtcPosition);

        // only add USDC supply position for now.
        cellar.addPositionToCatalogue(morphoBlueSupplyUSDCPosition);

        cellar.addPosition(1, wethPosition, abi.encode(true), false);
        cellar.addPosition(2, wbtcPosition, abi.encode(true), false);
        cellar.addPosition(3, morphoBlueSupplyUSDCPosition, abi.encode(true), false);

        cellar.setHoldingPosition(morphoBlueSupplyUSDCPosition);

        WETH.safeApprove(address(cellar), type(uint256).max);
        USDC.safeApprove(address(cellar), type(uint256).max);
        WBTC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();

        // tests that adaptor call for lending works when holding position is a position with morphoBlueSupplyAdaptor
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend USDC on Morpho Blue. Use the initial deposit that is in the cellar to begin with.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarket, initialDeposit);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        initialLend = _userSupplyBalance(usdcDaiMarketId, address(cellar));
        assertEq(
            initialLend,
            initialAssets,
            "Should be equal as the test setup includes lending initialDeposit of USDC into Morpho Blue"
        );
    }

    // Throughout all tests, setup() has supply usdc position fully trusted (cellar and registry), weth and wbtc supply positions trusted w/ registry. mbsupplyusdc position is holding position.

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertEq(USDC.balanceOf(address(cellar)), 0, "testDeposit: all assets should have been supplied to MB market.");
        assertApproxEqAbs(
            _userSupplyBalance(usdcDaiMarketId, address(cellar)),
            assets + initialAssets,
            1,
            "testDeposit: all assets should have been supplied to MB market."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        USDC.safeApprove(address(cellar), type(uint256).max);
        cellar.withdraw(assets / 2, address(this), address(this));

        assertEq(
            USDC.balanceOf(address(this)),
            assets / 2,
            "testWithdraw: half of assets should have been withdrawn to cellar."
        );
        assertApproxEqAbs(
            _userSupplyBalance(usdcDaiMarketId, address(cellar)),
            (assets / 2) + initialAssets,
            1,
            "testDeposit: half of assets from cellar should remain in MB market."
        );
        cellar.withdraw((assets / 2), address(this), address(this)); // NOTE - initialAssets is actually originally from the deployer.
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertEq(
            cellar.totalAssets(),
            assets + initialAssets,
            "testTotalAssets: Total assets MUST equal assets deposited + initialAssets."
        );
    }

    function testStrategistLendingUSDC(uint256 assets) external {
        cellar.setHoldingPosition(usdcPosition); // set holding position back to erc20Position

        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend USDC.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend USDC on Morpho Blue.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarket, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 newSupplyBalance = _userSupplyBalance(usdcDaiMarketId, address(cellar));
        // check supply share balance for cellar has increased.
        assertGt(newSupplyBalance, initialLend, "Cellar should have supplied more USDC to MB market");
        assertEq(newSupplyBalance, assets + initialAssets, "Rebalance should have lent all USDC on Morpho Blue.");
    }

    function testBalanceOfCalculationMethods(uint256 assets) external {
        cellar.setHoldingPosition(usdcPosition); // set holding position back to erc20Position

        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend USDC.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend USDC on Morpho Blue.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarket, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 newSupplyBalanceAccToMBLib = _userSupplyBalance(usdcDaiMarketId, address(cellar));
        uint256 supplyBalanceDirectFromMorphoBlue = uint256(
            (morphoBlue.position(usdcDaiMarketId, address(cellar)).supplyShares).toAssetsDown(
                uint256(morphoBlue.market(usdcDaiMarketId).totalSupplyAssets),
                uint256(morphoBlue.market(usdcDaiMarketId).totalSupplyShares)
            )
        );
        vm.startPrank(address(cellar));
        bytes memory adaptorData = abi.encode(usdcDaiMarket);

        uint256 balanceOfAccToSupplyAdaptor = morphoBlueSupplyAdaptor.balanceOf(adaptorData);

        assertEq(
            balanceOfAccToSupplyAdaptor,
            supplyBalanceDirectFromMorphoBlue,
            "balanceOf() should report same amount as morpho blue as long interest has been accrued beforehand."
        );
        assertEq(
            newSupplyBalanceAccToMBLib,
            supplyBalanceDirectFromMorphoBlue,
            "Checking that helper _userSupplyBalance() reports proper supply balances as long as interest has been accrued beforehand."
        );
        vm.stopPrank();
    }

    // w/ holdingPosition as morphoBlueSupplyUSDC, we make sure that strategists can lend to the holding position outright. ie.) some airdropped assets were swapped to USDC to use in morpho blue.
    function testStrategistLendWithHoldingPosition(uint256 assets) external {
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(cellar), assets);

        // Strategist rebalances to lend USDC.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend USDC on Morpho Blue.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(usdcDaiMarket, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 newSupplyBalance = _userSupplyBalance(usdcDaiMarketId, address(cellar));
        assertEq(newSupplyBalance, assets + initialAssets, "Rebalance should have lent all USDC on Morpho Blue.");
    }

    function testStrategistWithdrawing(uint256 assets) external {
        // Have user deposit into cellar.
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarket, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);
        assertEq(
            USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            "Cellar USDC should have been withdrawn from Morpho Blue Market."
        );
    }

    // lend assets into holdingPosition (morphoSupplyUSDCPosition, and then withdraw the USDC from it and lend it into a new market, wethUsdcMarketId (a different morpho blue usdc market))
    function testRebalancingBetweenPairs(uint256 assets) external {
        // Add another Morpho Blue Market to cellar
        cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(true), false);

        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw USDC from MB market
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarket, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarket, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 newSupplyBalance = _userSupplyBalance(wethUsdcMarketId, address(cellar));

        assertApproxEqAbs(
            newSupplyBalance,
            assets + initialAssets,
            2,
            "Rebalance should have lent all USDC on new Morpho Blue WETH:USDC market."
        );

        // Withdraw half the assets
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(wethUsdcMarket, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(
            USDC.balanceOf(address(cellar)),
            assets / 2,
            "Should have withdrawn half the assets from MB Market wethUsdcMarketId."
        );

        newSupplyBalance = _userSupplyBalance(wethUsdcMarketId, address(cellar));
        assertApproxEqAbs(
            newSupplyBalance,
            (assets / 2) + initialAssets,
            2,
            "Rebalance should have led to some assets withdrawn from MB Market wethUsdcMarketId."
        );
    }

    function testUsingMarketNotSetupAsPosition(uint256 assets) external {
        cellar.setHoldingPosition(usdcPosition); // set holding position back to erc20Position

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend USDC but with an untrusted market.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(UNTRUSTED_mbFakeMarket, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueHelperLogic.MorphoBlueAdaptors__MarketPositionsMustBeTracked.selector,
                    (UNTRUSTED_mbFakeMarket)
                )
            )
        );
        cellar.callOnAdaptor(data);

        vm.startPrank(address(cellar));
        bytes memory callData = abi.encodeWithSelector(
            morphoBlueSupplyAdaptor.deposit.selector,
            assets,
            abi.encode(UNTRUSTED_mbFakeMarket)
        );
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueHelperLogic.MorphoBlueAdaptors__MarketPositionsMustBeTracked.selector,
                    (UNTRUSTED_mbFakeMarket)
                )
            )
        );
        // cellar.withdraw(assets, address(this), address(this));
        address(morphoBlueSupplyAdaptor).functionDelegateCall(callData);
        vm.stopPrank();
    }

    // Needed for tests so this contract can act like a cellar.
    function isPositionUsed(uint256) public pure returns (bool) {
        return false;
    }

    // Check that loanToken in multiple different pairs is correctly accounted for in totalAssets().
    function testMultiplePositionsTotalAssets(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e6, 100_000_000e6);
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of loanToken (where we've made it the same one for these tests) to distribute between three different morpho blue markets
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        assertApproxEqAbs(
            assets + initialAssets,
            cellar.totalAssets(),
            2,
            "Total assets should have been lent out and are accounted for via MorphoBlueSupplyAdaptor positions."
        );

        assertApproxEqAbs(
            _userSupplyBalance(usdcDaiMarketId, address(cellar)),
            dividedAssetPerMultiPair + initialAssets,
            2,
            "testMultiplePositionsTotalAssets: cellar should have assets supplied to usdcDaiMarketId."
        );
        assertApproxEqAbs(
            _userSupplyBalance(wethUsdcMarketId, address(cellar)),
            dividedAssetPerMultiPair,
            2,
            "testMultiplePositionsTotalAssets: cellar should have assets supplied to wethUsdcMarket."
        );
        assertApproxEqAbs(
            _userSupplyBalance(wbtcUsdcMarketId, address(cellar)),
            dividedAssetPerMultiPair,
            2,
            "testMultiplePositionsTotalAssets: cellar should have assets supplied to wbtcUsdcMarketId."
        );
    }

    // Check that user able to withdraw from multiple lending positions outright
    function testMultiplePositionsUserWithdraw(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e6, 100_000_000e6);
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of loanToken to distribute between different markets
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        deal(address(USDC), address(this), 0);
        uint256 withdrawAmount = cellar.maxWithdraw(address(this));
        cellar.withdraw(withdrawAmount, address(this), address(this));

        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            withdrawAmount,
            1,
            "User should have gotten all their USDC (minus some dust)"
        );
        assertEq(
            USDC.balanceOf(address(this)),
            withdrawAmount,
            "User should have gotten all their USDC (minus some dust)"
        );
    }

    function testWithdrawableFrom() external {
        cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(true), false);
        // Strategist rebalances to withdraw USDC, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw USDC from Morpho Blue.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarket, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarket, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        // Make cellar deposits lend USDC into WETH Pair by default
        cellar.setHoldingPosition(morphoBlueSupplyWETHPosition);
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        // Figure out how much the whale must borrow to borrow all the loanToken.
        uint256 totalLoanTokenSupplied = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
        uint256 totalLoanTokenBorrowed = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);
        uint256 assetsToBorrow = totalLoanTokenSupplied > totalLoanTokenBorrowed
            ? totalLoanTokenSupplied - totalLoanTokenBorrowed
            : 0;
        // Supply 2x the value we are trying to borrow in weth market collateral (WETH)
        uint256 collateralToProvide = priceRouter.getValue(USDC, 2 * assetsToBorrow, WETH);
        deal(address(WETH), whaleBorrower, collateralToProvide);
        vm.startPrank(whaleBorrower);
        WETH.approve(address(morphoBlue), collateralToProvide);
        MarketParams memory market = morphoBlue.idToMarketParams(wethUsdcMarketId);
        morphoBlue.supplyCollateral(market, collateralToProvide, whaleBorrower, hex"");
        // now borrow
        morphoBlue.borrow(market, assetsToBorrow, 0, whaleBorrower, whaleBorrower);
        vm.stopPrank();
        uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();
        assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");
        // Whale repays half of their debt.
        uint256 sharesToRepay = (morphoBlue.position(wethUsdcMarketId, whaleBorrower).borrowShares) / 2;
        vm.startPrank(whaleBorrower);
        USDC.approve(address(morphoBlue), assetsToBorrow);
        morphoBlue.repay(market, 0, sharesToRepay, whaleBorrower, hex"");
        vm.stopPrank();
        uint256 totalLoanTokenSupplied2 = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
        uint256 totalLoanTokenBorrowed2 = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);
        uint256 liquidLoanToken2 = totalLoanTokenSupplied2 - totalLoanTokenBorrowed2;
        assetsWithdrawable = cellar.totalAssetsWithdrawable();
        assertEq(assetsWithdrawable, liquidLoanToken2, "Should be able to withdraw liquid loanToken.");
        // Have user withdraw the loanToken.
        deal(address(USDC), address(this), 0);
        cellar.withdraw(liquidLoanToken2, address(this), address(this));
        assertEq(USDC.balanceOf(address(this)), liquidLoanToken2, "User should have received liquid loanToken.");
    }

    // NOTE - This fuzz test has larger bounds compared to the other fuzz tests because the IRM used within these tests paired w/ the test market conditions means we either have to skip large amounts of time or work with large amounts of fuzz bounds. When the fuzz bounds are the other ones we used before, this test reverts w/ Cellar__TotalAssetDeviatedOutsideRange when we skip 1 day or more, and it doesn't seem to show accrued interest when skipping less than that. The irm shows borrowRate changes though based on utilization as per the mockIrm setup.
    function testAccrueInterest(uint256 assets) external {
        assets = bound(assets, 1_000e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        uint256 balance1 = (_userSupplyBalance(usdcDaiMarketId, address(cellar)));

        skip(1 days);
        mockUsdcUsd.setMockUpdatedAt(block.timestamp);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        // Strategist rebalances to accrue interest in markets
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAccrueInterestOnMorphoBlue(usdcDaiMarket);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);
        uint256 balance2 = (_userSupplyBalance(usdcDaiMarketId, address(cellar)));

        assertEq(balance2, balance1, "No interest accrued since no loans were taken out.");

        // provide collateral
        uint256 collateralToProvide = priceRouter.getValue(USDC, 2 * assets, DAI);
        deal(address(DAI), whaleBorrower, collateralToProvide);
        vm.startPrank(whaleBorrower);
        DAI.approve(address(morphoBlue), collateralToProvide);
        MarketParams memory market = morphoBlue.idToMarketParams(usdcDaiMarketId);
        morphoBlue.supplyCollateral(market, collateralToProvide, whaleBorrower, hex"");

        // now borrow
        morphoBlue.borrow(market, assets / 5, 0, whaleBorrower, whaleBorrower);
        vm.stopPrank();

        skip(1 days);

        mockUsdcUsd.setMockUpdatedAt(block.timestamp);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAccrueInterestOnMorphoBlue(usdcDaiMarket);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 balance3 = (_userSupplyBalance(usdcDaiMarketId, address(cellar)));

        assertGt(balance3, balance2, "Supplied loanAsset into MorphoBlue should have accrued interest.");
    }

    function testWithdrawWhenIlliquid(uint256 assets) external {
        assets = bound(assets, 0.01e6, 100_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Check logic in the withdraw function by having strategist call withdraw, passing in isLiquid = false.
        bool isLiquid = false;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                MorphoBlueSupplyAdaptor.withdraw.selector,
                assets,
                address(this),
                abi.encode(usdcDaiMarket),
                abi.encode(isLiquid)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);

        vm.startPrank(address(cellar));
        uint256 withdrawableFrom = morphoBlueSupplyAdaptor.withdrawableFrom(abi.encode(0), abi.encode(isLiquid));
        vm.stopPrank();

        assertEq(withdrawableFrom, 0, "Since it is illiquid it should be zero.");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    // setup multiple lending positions
    function _setupMultiplePositions(uint256 dividedAssetPerMultiPair) internal {
        // add numerous USDC markets atop of holdingPosition

        cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        cellar.addPositionToCatalogue(morphoBlueSupplyWBTCPosition);

        cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(true), false);
        cellar.addPosition(5, morphoBlueSupplyWBTCPosition, abi.encode(true), false);

        // Strategist rebalances to withdraw set amount of USDC, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Withdraw 2/3 of cellar USDC from one MB market, then redistribute to other MB markets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarket, dividedAssetPerMultiPair * 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarket, dividedAssetPerMultiPair);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wbtcUsdcMarket, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);
    }

    /**
     * NOTE: make sure to call `accrueInterest()` on respective market before calling these helpers
     */
    function _userSupplyBalance(Id _id, address _user) internal view returns (uint256) {
        Market memory market = morphoBlue.market(_id);
        // this currently doesn't account for interest, that needs to be done before calling this helper.
        return (morphoBlue.supplyShares(_id, _user).toAssetsDown(market.totalSupplyAssets, market.totalSupplyShares));
    }
}
