// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Adaptors
import { DSRAdaptor, DSRManager } from "src/modules/adaptors/Maker/DSRAdaptor.sol";

import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

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
        uint256 blockNumber = 16869780;
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

        cellar.redeem(maxRedeem, address(this), address(this));
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

        console.log("TA", cellar.totalAssets());

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

        uint256 bal = manager.daiBalance(address(cellar));
        assertGt(bal, 0, "Balance should have left pending yield in DSR.");
    }
}
