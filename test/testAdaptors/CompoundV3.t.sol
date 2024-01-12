// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IComet } from "src/interfaces/external/Compound/IComet.sol";
import { SupplyAdaptor } from "src/modules/adaptors/Compound/V3/SupplyAdaptor.sol";
import { CollateralAdaptor } from "src/modules/adaptors/Compound/V3/CollateralAdaptor.sol";
import { BorrowAdaptor } from "src/modules/adaptors/Compound/V3/BorrowAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarCompoundTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    SupplyAdaptor private supplyAdaptor;
    CollateralAdaptor private collateralAdaptor;
    BorrowAdaptor private borrowAdaptor;

    IComet private comet = IComet(cUSDCV3);

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private compPosition = 4;
    uint32 private uniPosition = 5;
    uint32 private linkPosition = 6;
    uint32 private wethCompoundV3CollateralPosition = 7;
    uint32 private wbtcCompoundV3CollateralPosition = 8;
    uint32 private compCompoundV3CollateralPosition = 9;
    uint32 private uniCompoundV3CollateralPosition = 10;
    uint32 private linkCompoundV3CollateralPosition = 11;
    uint32 private usdcCompoundV3SupplyPosition = 12;
    uint32 private usdcCompoundV3DebtPosition = 13;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        supplyAdaptor = new SupplyAdaptor();
        collateralAdaptor = new CollateralAdaptor(1.05e18);
        borrowAdaptor = new BorrowAdaptor(1.05e18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(LINK_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, LINK_USD_FEED);
        priceRouter.addAsset(LINK, settings, abi.encode(stor), price);

        stor.inETH = true;
        price = uint256(IChainlinkAggregator(UNI_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, UNI_ETH_FEED);
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(supplyAdaptor));
        registry.trustAdaptor(address(collateralAdaptor));
        registry.trustAdaptor(address(borrowAdaptor));

        // Add ERC20 positions.
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(compPosition, address(erc20Adaptor), abi.encode(COMP));
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));
        registry.trustPosition(linkPosition, address(erc20Adaptor), abi.encode(LINK));

        // Add Compound V3 Supply position.
        registry.trustPosition(usdcCompoundV3SupplyPosition, address(supplyAdaptor), abi.encode(cUSDCV3));

        // Add Compounds V3 Collateral positions.
        registry.trustPosition(wethCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, WETH));
        registry.trustPosition(wbtcCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, WBTC));
        registry.trustPosition(compCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, COMP));
        registry.trustPosition(uniCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, UNI));
        registry.trustPosition(linkCompoundV3CollateralPosition, address(collateralAdaptor), abi.encode(cUSDCV3, LINK));

        // Add Compound V3 Debt position.
        registry.trustPosition(usdcCompoundV3DebtPosition, address(borrowAdaptor), abi.encode(cUSDCV3));

        string memory cellarName = "Compound Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        cellar.addAdaptorToCatalogue(address(supplyAdaptor));
        cellar.addAdaptorToCatalogue(address(collateralAdaptor));
        cellar.addAdaptorToCatalogue(address(borrowAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPositionToCatalogue(compPosition);
        cellar.addPositionToCatalogue(uniPosition);
        cellar.addPositionToCatalogue(linkPosition);
        cellar.addPositionToCatalogue(wethCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(wbtcCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(compCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(uniCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(linkCompoundV3CollateralPosition);
        cellar.addPositionToCatalogue(usdcCompoundV3SupplyPosition);
        cellar.addPositionToCatalogue(usdcCompoundV3DebtPosition);

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Add cUSDCV3 Supply position, and set as holding position.
        cellar.addPosition(0, usdcCompoundV3SupplyPosition, abi.encode(true), false);
        cellar.setHoldingPosition(usdcCompoundV3SupplyPosition);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            comet.balanceOf(address(cellar)),
            assets,
            2,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Add cUSDCV3 Supply position, and set as holding position.
        cellar.addPosition(0, usdcCompoundV3SupplyPosition, abi.encode(true), false);
        cellar.setHoldingPosition(usdcCompoundV3SupplyPosition);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        // Withdraw from Cellar.
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertApproxEqAbs(USDC.balanceOf(address(this)), assets, 1, "Amount withdrawn should equal assets.");
    }

    // TODO test checking total assets if in multiple compound positions
    // TODO test checking a strategist trying to use untrusted input args.
    // TODO test checking max available logic
    // TODO test where we have multiple assets as collateral, and we use a ton of fuzzing and check that the health factor logic is as expected.

    function testHappyPath(uint256 assets) external {
        // Use 200 for min assets because the minimum borrow is 100 USDC.
        assets = bound(assets, 200e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);

        // Deposit into Cellar.
        cellar.deposit(assets, address(this));

        // Simulate a swap by minting Cellar ERC20s.
        uint256 assetsInWeth = priceRouter.getValue(USDC, assets, WETH);
        deal(address(USDC), address(cellar), initialAssets);
        deal(address(WETH), address(cellar), assetsInWeth);

        // Add collateral and borrow assets.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSupplyCollateralToCompoundV3(comet, WETH, assetsInWeth);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrowBaseFromCompoundV3(comet, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedUsdcBalance = initialAssets + assets / 2;
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            expectedUsdcBalance,
            1,
            "USDC Balance of cellar should equal initialAssets + assets / 2."
        );

        uint256 expectedHealthFactor = 1.8e18;
        uint256 actualHealthFactor = borrowAdaptor.getAccountHealthFactor(comet, address(cellar));
        assertApproxEqRel(actualHealthFactor, expectedHealthFactor, 0.01e18, "Health Factor should equal expected.");
        // TODO I could make above calculation better if I used Compound V3s pricing when figuring out assetsInWeth.

        // Repay debt, and withdraw collateral.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepayBaseToCompoundV3(comet, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(borrowAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawCollateralFromCompoundV3(comet, WETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 expectedWethBalance = assetsInWeth;
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            expectedWethBalance,
            1,
            "WETH Balance of cellar should equal assetsInWeth."
        );
    }
}
