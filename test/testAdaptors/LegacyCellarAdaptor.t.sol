// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { LegacyCellarAdaptor } from "src/modules/adaptors/Sommelier/LegacyCellarAdaptor.sol";
import { LegacyRegistry } from "src/interfaces/LegacyRegistry.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract LegacyCellarAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    LegacyCellarAdaptor private cellarAdaptor;
    ERC4626SharePriceOracle private sharePriceOracle;
    Cellar private cellar;
    Cellar private metaCellar;

    MockDataFeed private mockUsdcUsd;

    uint32 private usdcPosition = 1;
    uint32 private cellarPosition = 2;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18364794;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        cellarAdaptor = new LegacyCellarAdaptor();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockUsdcUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        string memory cellarName = "Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        // Setup Share Price Oracle.
        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup share price oracle.
        {
            ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
                _target,
                _heartbeat,
                _deviationTrigger,
                _gracePeriod,
                _observationsToUse,
                _automationRegistry,
                _automationRegistrar,
                _automationAdmin,
                address(LINK),
                1e18,
                0.1e4,
                10e4,
                address(0),
                0
            );
            sharePriceOracle = new ERC4626SharePriceOracle(args);
        }

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Write storage to change forwarder to address this.
        stdstore.target(address(sharePriceOracle)).sig(sharePriceOracle.automationForwarder.selector).checked_write(
            address(this)
        );

        registry.trustAdaptor(address(cellarAdaptor));
        registry.trustPosition(cellarPosition, address(cellarAdaptor), abi.encode(cellar, sharePriceOracle));

        cellarName = "Meta Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;

        metaCellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        metaCellar.addAdaptorToCatalogue(address(cellarAdaptor));
        metaCellar.addPositionToCatalogue(cellarPosition);
        metaCellar.addPosition(1, cellarPosition, abi.encode(0), false);

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        deal(address(USDC), address(this), type(uint256).max);
        USDC.safeApprove(address(metaCellar), type(uint256).max);
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e6, 10_000_000e6);
        metaCellar.deposit(assets, address(this));

        uint256 totalAssetsBefore = metaCellar.totalAssets();

        _depositIntoCellar(assets);

        uint256 totalAssetsAfter = metaCellar.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets should not have changed.");
    }

    function testOracleFailureResultsInPriceCalculatedFromScratch(uint256 assets) external {
        assets = bound(assets, 0.1e6, 10_000_000e6);
        metaCellar.deposit(assets, address(this));

        uint256 totalAssetsBefore = metaCellar.totalAssets();

        (, bool isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(!isNotSafeToUse, "Oracle should be safe to use.");

        _depositIntoCellar(assets);

        // Advance time forward so that oracle answer is stale.
        vm.warp(block.timestamp + (1 days + 3_601));
        mockUsdcUsd.setMockUpdatedAt(block.timestamp);

        (, isNotSafeToUse) = sharePriceOracle.getLatestAnswer();
        assertTrue(isNotSafeToUse, "Oracle should not be safe to use.");

        // Even though oracle failed, Cellar shares can still be priced.
        uint256 totalAssetsAfter = metaCellar.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets should not have changed.");
    }

    function testHowRealSharePriceDeviatingFromOracleAffectsMetaCellar(uint256 assets) external {
        assets = bound(assets, 0.1e6, 10_000_000e6);
        metaCellar.deposit(assets, address(this));

        metaCellar.setRebalanceDeviation(0.006e18);

        uint256 totalAssetsBefore = metaCellar.totalAssets();

        _depositIntoCellar(assets);

        // Have cellar share price decrease by 50 bps.
        uint256 newUsdcBalanceForCellar = USDC.balanceOf(address(cellar)).mulDivDown(0.9950e4, 1e4);
        deal(address(USDC), address(cellar), newUsdcBalanceForCellar);

        // Since movement was not enough to update oracle, totalAssets stays the same.
        uint256 totalAssetsAfter = metaCellar.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets should not have changed.");

        // But when strategist withdraws, totalAssets will decrease.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromLegacyCellar(
                address(cellar),
                type(uint256).max,
                address(sharePriceOracle)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        metaCellar.callOnAdaptor(data);

        uint256 totalAssetsAfterWithdrawFromCellar = metaCellar.totalAssets();
        assertLt(totalAssetsAfterWithdrawFromCellar, totalAssetsBefore, "totalAssets should decreased changed.");
    }

    function _depositIntoCellar(uint256 assets) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToLegacyCellar(
                address(cellar),
                assets,
                address(sharePriceOracle)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        metaCellar.callOnAdaptor(data);
    }
}
