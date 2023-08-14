// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Adaptors
import { DSRAdaptor, DSRManager, Pot } from "src/modules/adaptors/Maker/DSRAdaptor.sol";

import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { IRYUSDRegistry } from "src/interfaces/IRYUSDRegistry.sol";

interface IRYUSDCellar {
    function setupAdaptor(address adaptor) external;
}

contract CellarDSRTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    DSRAdaptor public dsrAdaptor;

    Cellar public cellar;
    MockDataFeed public mockDaiUsd;

    uint256 initialAssets;

    DSRManager public manager = DSRManager(dsrManager);

    uint32 daiPosition = 1;
    uint32 dsrPosition = 2;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17914165;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        dsrAdaptor = new DSRAdaptor(dsrManager);

        mockDaiUsd = new MockDataFeed(DAI_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(address(mockDaiUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockDaiUsd));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        registry.trustAdaptor(address(dsrAdaptor));

        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(dsrPosition, address(dsrAdaptor), abi.encode(0));

        string memory cellarName = "DSR Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, DAI, daiPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.addAdaptorToCatalogue(address(dsrAdaptor));
        cellar.addPositionToCatalogue(dsrPosition);

        cellar.addPosition(0, dsrPosition, abi.encode(0), false);
        cellar.setHoldingPosition(dsrPosition);

        DAI.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

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

        console.log("TA", cellar.totalAssets());

        uint256 assetsBefore = cellar.totalAssets();

        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            cellar.totalAssets(),
            assetsBefore,
            "Assets should not have increased because nothing has interacted with dsr."
        );

        uint256 bal = manager.daiBalance(address(cellar));
        assertGt(bal, assets, "Balance should have increased.");

        uint256 assetsAfter = cellar.totalAssets();

        assertGt(assetsAfter, assetsBefore, "Total Assets should have increased.");
    }

    function testUsersDoNotGetPendingInterest(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBefore = cellar.totalAssets();

        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            cellar.totalAssets(),
            assetsBefore,
            "Assets should not have increased because nothing has interacted with dsr."
        );

        uint256 maxRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(maxRedeem, address(this), address(this));

        assertApproxEqAbs(DAI.balanceOf(address(this)), assets, 3, "Should have sent DAI to the user.");

        uint256 bal = manager.daiBalance(address(cellar));
        assertGt(bal, 0, "Balance should have left pending yield in DSR.");
    }

    function testStrategistFunctions(uint256 assets) external {
        cellar.setHoldingPosition(daiPosition);

        cellar.setRebalanceDeviation(0.005e18);

        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Deposit half the DAI into DSR.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToJoinDsr(assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(dsrAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 cellarDsrBalance = manager.daiBalance(address(cellar));

        assertApproxEqAbs(cellarDsrBalance, assets / 2, 2, "Should have deposited half the assets into the DSR.");

        // Advance some time.
        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        // Deposit remaining assets into DSR.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToJoinDsr(type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(dsrAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // console.log(Pot(manager.pot()).chi());

        cellarDsrBalance = manager.daiBalance(address(cellar));
        assertGt(cellarDsrBalance, assets + initialAssets, "Should have deposited all the assets into the DSR.");

        // Advance some time.
        vm.warp(block.timestamp + 10 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        // Withdraw half the assets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToExitDsr(assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(dsrAdaptor), callData: adaptorCalls });
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
            adaptorCalls[0] = _createBytesDataToExitDsr(type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(dsrAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertGt(
            DAI.balanceOf(address(cellar)),
            assets + initialAssets,
            "Should have withdrawn all the assets from the DSR."
        );
    }

    function testDrip(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBefore = cellar.totalAssets();

        vm.warp(block.timestamp + 1 days);
        mockDaiUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            cellar.totalAssets(),
            assetsBefore,
            "Assets should not have increased because nothing has interacted with dsr."
        );

        // Strategist calls drip.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDrip();
            data[0] = Cellar.AdaptorCall({ adaptor: address(dsrAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 assetsAfter = cellar.totalAssets();

        assertGt(assetsAfter, assetsBefore, "Total Assets should have increased.");
    }

    /**
     * @notice Test RYUSD (w/ its older cellar architecture can work w/ sDAI)
     * @dev Risk assessments shouldn't matter
     */
    function testRYUSDIntegration() external {
        // assets = bound(assets, 0.1e18, 1_000_000_000e18);
        uint256 assets = 1e18;
        ERC4626 sDai = ERC4626(savingsDaiAddress);
        uint32 sDaiPosition = 29; // Take current position count and add 1.

        CellarAdaptor cellarAdaptor = new CellarAdaptor();
        IRYUSDRegistry ryusdRegistryInterface = IRYUSDRegistry(ryusdRegistry);
        Cellar RYUSDCellar = Cellar(ryusdCellar);
        initialAssets = RYUSDCellar.totalAssets();

        vm.startPrank(ryusdRegistryOwner);
        // go to RYUSD registry & trust cellar adaptor & trust position
        ryusdRegistryInterface.trustAdaptor(address(cellarAdaptor), 0, 0);
        ryusdRegistryInterface.trustPosition(address(cellarAdaptor), abi.encode(sDai), 0, 0);
        vm.stopPrank();

        // addPosition on RYUSD cellar
        vm.startPrank(gravityBridgeAddress);
        RYUSDCellar.removePosition(15, false);
        RYUSDCellar.addPosition(0, sDaiPosition, abi.encode(true), false);
        IRYUSDCellar(address(ryusdCellar)).setupAdaptor(address(cellarAdaptor));
        vm.stopPrank();

        // At this point you can deal RYUSD some DAI, and make sure it can enter/exit sDAI
        deal(address(DAI), ryusdCellar, assets);

        vm.startPrank(gravityBridgeAddress);
        // Deposit half of RYUSD's DAI into DSR
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(savingsDaiAddress, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }

        RYUSDCellar.callOnAdaptor(data);

        uint256 assetsInSDai = sDai.maxWithdraw(ryusdCellar);
        assertApproxEqAbs(assetsInSDai, assets / 2, 2, "Should have deposited half the assets into the DSR.");

        // Deposit remaining assets into DSR.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(savingsDaiAddress, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        RYUSDCellar.callOnAdaptor(data);

        assetsInSDai = sDai.maxWithdraw(ryusdCellar);
        assertApproxEqAbs(assetsInSDai, assets, 10, "Should have deposited all the assets into the DSR.");

        // Withdraw half the assets.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCellar(address(sDai), assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        RYUSDCellar.callOnAdaptor(data);

        assertApproxEqAbs(
            DAI.balanceOf(address(ryusdCellar)),
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
        RYUSDCellar.callOnAdaptor(data);

        assertApproxEqAbs(
            DAI.balanceOf(address(ryusdCellar)),
            assets,
            10,
            "Should have withdrawn all the assets from the DSR."
        );

        assetsInSDai = sDai.maxWithdraw(address(cellar));
        assertEq(assetsInSDai, 0, "No assets should be left in DSR.");
        vm.stopPrank();
    }
}
