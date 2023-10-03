// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarAdaptorWithSDaiTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarAdaptor private cellarAdaptor;
    ERC4626 public sDai = ERC4626(savingsDaiAddress);
    Cellar private cellar;
    MockDataFeed public mockDaiUsd;

    uint32 private daiPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private sDaiPosition = 3;

    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        cellarAdaptor = new CellarAdaptor();

        mockDaiUsd = new MockDataFeed(DAI_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockDaiUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockDaiUsd));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));

        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(sDaiPosition, address(cellarAdaptor), abi.encode(sDai));

        string memory cellarName = "Savings DAI Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, DAI, daiPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
        cellar.addPositionToCatalogue(sDaiPosition);

        cellar.addPosition(0, sDaiPosition, abi.encode(true), false);

        cellar.setHoldingPosition(sDaiPosition);

        DAI.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsInSDai = sDai.maxWithdraw(address(cellar));
        assertApproxEqAbs(assetsInSDai, assets, 2, "Assets should have been deposited into sDai.");

        assertApproxEqAbs(
            cellar.totalAssets(),
            initialAssets + assets,
            2,
            "Cellar totalAssets should equal assets + initial assets"
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        assets = cellar.redeem(maxRedeem, address(this), address(this));

        assertApproxEqAbs(DAI.balanceOf(address(this)), assets, 2, "User should have been sent DAI.");
    }

    function testInterestAccrual(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBefore = cellar.totalAssets();

        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        assertGt(
            cellar.totalAssets(),
            assetsBefore,
            "Assets should have increased because sDAI calculates pending interest."
        );
    }

    function testUsersGetPendingInterest(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBefore = cellar.totalAssets();

        vm.warp(block.timestamp + 10 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        assertGt(
            cellar.totalAssets(),
            assetsBefore,
            "Assets should have increased because sDAI calculates pending interest."
        );

        uint256 maxRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(maxRedeem, address(this), address(this));

        assertGt(DAI.balanceOf(address(this)), assets, "Should have sent more DAI to the user than they put in.");
    }

    function testStrategistFunctions(uint256 assets) external {
        cellar.setHoldingPosition(daiPosition);

        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Deposit half the DAI into DSR.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(sDai), assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 assetsInSDai = sDai.maxWithdraw(address(cellar));

        assertApproxEqAbs(assetsInSDai, assets / 2, 2, "Should have deposited half the assets into the DSR.");

        // Advance some time.
        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        // Deposit remaining assets into DSR.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(sDai), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assetsInSDai = sDai.maxWithdraw(address(cellar));
        assertGt(assetsInSDai, assets + initialAssets, "Should have deposited all the assets into the DSR.");

        // Advance some time.
        vm.warp(block.timestamp + 10 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        // Withdraw half the assets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCellar(address(sDai), assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Should have withdrawn half the assets from the DSR."
        );

        // Withdraw remaining  assets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCellar(address(sDai), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertGt(
            DAI.balanceOf(address(cellar)),
            assets + initialAssets,
            "Should have withdrawn all the assets from the DSR."
        );

        assetsInSDai = sDai.maxWithdraw(address(cellar));
        assertEq(assetsInSDai, 0, "No assets should be left in DSR.");
    }
}
