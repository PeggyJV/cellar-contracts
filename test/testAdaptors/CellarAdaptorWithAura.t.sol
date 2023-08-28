// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { IBaseRewardPool } from "src/interfaces/external/Aura/IBaseRewardPool.sol";

contract CellarAdaptorWithAuraTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarAdaptor private cellarAdaptor;
    ERC4626 public auraPoolExample = ERC4626(auraPoolExampleAddress);
    Cellar private cellar;
    // MockDataFeed public mockDaiUsd;
    MockDataFeed public mockBptUsd;

    uint32 private daiPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private auraRethWethBptPoolPosition = 3;
    uint32 private rETH_wETH_BPT_Position = 4;

    uint256 public initialAssets;

    // TODO: use rETH_wETH_BPT for tests, but we need to create a fair mock pricing.
    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        cellarAdaptor = new CellarAdaptor();

        // TODO: setup mock price feed for bpt interacting with aura pool in tests
        mockBptUsd = new MockDataFeed(DAI_USD_FEED); // TODO: set one up and specify for rETH_wETH_BPT_Position, but we won't have a chainlink price feed per se so...
        // mockDaiUsd = new MockDataFeed(DAI_USD_FEED); // TODO: set one up and specify for what bpt

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockBptUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockBptUsd));
        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));

        // TODO: trust the cellar adaptor position with the auraPool
        registry.trustPosition(rETH_wETH_BPT_Position, address(erc20Adaptor), abi.encode(rETH_wETH_BPT));
        registry.trustPosition(auraRethWethBptPoolPosition, address(cellarAdaptor), abi.encode(auraPoolExampleAddress));

        string memory cellarName = "rETH-wETH BPT Aura Pool Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(
            cellarName,
            rETH_wETH_BPT,
            rETH_wETH_BPT_Position,
            abi.encode(0),
            initialDeposit,
            platformCut
        );

        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
        cellar.addPositionToCatalogue(auraRethWethBptPoolPosition);

        cellar.addPosition(0, auraRethWethBptPoolPosition, abi.encode(true), false);

        cellar.setHoldingPosition(auraRethWethBptPoolPosition);

        rETH_wETH_BPT.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    // setup includes: Registry trusting adaptors and positions, creating cellar with BPT as the base asset, adding adaptor to the cellar catalogue, adding the positions and setting holding position, approving the handling of BPT to cellar on behalf of this test address.
    // deposit test: ensure that cellar deposit leads to transferance of BPT to aura pool. Cellar should get back aura-vault or aura-pool tokens back as receipts/shares to the auraPool.
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsInAuraPool = auraPoolExampleAddressToken.balanceOf(address(cellar)); // TODO: add auraPoolExampleAddressToken constant that corresponds to the token receipt that is received from aura pool when depositing BPT
        assertApproxEqAbs(assetsInAuraPool, assets, 2, "Assets should have been deposited into assetsInAuraPool.");

        assertApproxEqAbs(
            cellar.totalAssets(),
            initialAssets + assets,
            2,
            "Cellar totalAssets should equal assets + initial assets"
        );
    }

    // withdraw test: ensure that cellar withdraw leads to transferance of BPT from aura pool back to cellar. Cellar should get back BPTs and have their aura receipts burnt.
    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        assets = cellar.redeem(maxRedeem, address(this), address(this));

        assertApproxEqAbs(rETH_wETH_BPT.balanceOf(address(this)), assets, 2, "User should have been sent DAI."); // TODO: confirm that this all works with the Aura Pool of course.
    }

    // TODO: rewards are going to be handled by other Aura adaptor: `AuraExtrasAdaptor.sol` so this test may not be here. Could have this test just check that we receive the BPTs initially deposited even after a long time. Rewards are in the form of tokens that are not the base asset BPT.
    function testInterestAccrual(uint256 assets) external {}

    // NOTE: Strategist functions are simply the base functions, so no tests are likely needed.
    function testStrategistFunctions(uint256 assets) external {}
}
