// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { IBaseRewardPool } from "src/interfaces/external/Aura/IBaseRewardPool.sol";

import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import { IVault, IAsset, IERC20, IFlashLoanRecipient } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { MockBalancerPoolAdaptor } from "src/mocks/adaptors/MockBalancerPoolAdaptor.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { CellarWithBalancerFlashLoans } from "src/base/permutations/CellarWithBalancerFlashLoans.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { AuraExtrasAdaptor } from "src/modules/adaptors/Aura/AuraExtraAdaptor.sol";

/**
 * @title CellarAdaptorWithAuraTest
 * @author 0xEinCodes
 * @notice Cellar Adaptor tests with Aura BPT Pools
 * @dev Mock datafeeds to be used for underlying BPTs. For tests, we'll go with rETH / wETH BPT pair. We'll use mock datafeeds for the constituent assets of this pair so we can warp forward to simulate reward accrual.
 * TODO: test with other AuraPools perhaps?
 */
contract CellarAdaptorWithAuraTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarAdaptor private cellarAdaptor;
    AuraExtrasAdaptor private auraExtrasAdaptor;
    ERC4626 public auraRETHWETHBPT = ERC4626(aura_rETH_wETH_BPT);
    Cellar private cellar;

    // Chainlink PriceFeeds
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockRethUsd;
    BalancerStablePoolExtension private balancerStablePoolExtension;

    uint32 private wethPosition = 1;
    uint32 private rethPosition = 2;
    uint32 private rETH_wETH_BPT_Position = 3;
    uint32 private auraRethWethBptPoolPosition = 4;
    uint32 private balPosition = 5;
    uint32 private auraPosition = 6;

    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        cellarAdaptor = new CellarAdaptor();
        auraExtrasAdaptor = new AuraExtrasAdaptor();

        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, IVault(vault));
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockRethUsd = new MockDataFeed(RETH_ETH_FEED);

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(BAL_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BAL_USD_FEED);
        priceRouter.addAsset(BAL, settings, abi.encode(stor), price);

        // TODO: AURA doesn't have an AURA_USD Chainlink Feed. For now, we'll make it a mock price feed with WETH FEED
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(AURA, settings, abi.encode(stor), price);

        // Add rETH_wETH_BPT pricing.
        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings; // TODO: get underlying order correct
        underlyings[0] = WETH;
        underlyings[1] = rETH;
        BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
            .ExtensionStorage({
                poolId: bytes32(0),
                poolDecimals: 18,
                rateProviderDecimals: rateProviderDecimals,
                rateProviders: rateProviders,
                underlyingOrConstituent: underlyings
            });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(extensionStor), 1e8);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));

        // TODO: trust the cellar adaptor position with the auraPool
        registry.trustPosition(rETH_wETH_BPT_Position, address(erc20Adaptor), abi.encode(rETH_wETH_BPT));
        registry.trustPosition(balPosition, address(erc20Adaptor), abi.encode(BAL));
        registry.trustPosition(auraPosition, address(erc20Adaptor), abi.encode(AURA));
        registry.trustPosition(auraRethWethBptPoolPosition, address(cellarAdaptor), abi.encode(aura_rETH_wETH_BPT));

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

        cellar.addPositionToCatalogue(auraRethWethBptPoolPosition);
        cellar.addPosition(0, auraRethWethBptPoolPosition, abi.encode(true), false);

        cellar.addPositionToCatalogue(auraRethWethBptPoolPosition);
        cellar.addPosition(0, auraRethWethBptPoolPosition, abi.encode(true), false);

        cellar.setHoldingPosition(auraRethWethBptPoolPosition);

        rETH_wETH_BPT.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    // deposit test: ensure that cellar deposit leads to transferance of BPT to aura pool. Cellar should get back aura-vault or aura-pool tokens back as receipts/shares to the auraPool.
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsInAuraPool = auraRETHWETHBPT.balanceOf(address(cellar)); // as per Aura BaseRewardPool4626.sol - this is ASSUMING 1:1 for BPT (vault asset) : AuraBPT (shareToken)

        // TODO: go with approx asserts if there is some slight noise.
        // assertApproxEqAbs(assetsInAuraPool, assets, 2, "Assets should have been deposited into assetsInAuraPool.");
        // assertApproxEqAbs(
        //     cellar.totalAssets(),
        //     initialAssets + assets,
        //     2,
        //     "Cellar totalAssets should equal assets + initial assets"
        // );

        assertEq(assetsInAuraPool, assets, "Assets should have been deposited into assetsInAuraPool 1:1.");
        assertEq(
            cellar.totalAssets(),
            initialAssets + assets,
            "Cellar totalAssets should equal assets + initial assets, 1:1"
        );
    }

    // withdraw test: ensure that cellar withdraw leads to transferance of BPT from aura pool back to cellar. Cellar should get back BPTs and have their aura receipts burnt.
    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this) // TODO: confirm that this all works with the Aura Pool of course.

        assertApproxEqAbs(assets, redeemedAssets, 2, "User should have been sent vault assets.");
        assertApproxEqAbs(
            auraRETHWETHBPT.balanceOf(address(this)),
            redeemedAssets,
            2,
            "User should have been sent vault assets."
        );
    }

    // same as redeem test but with a long time within the vault. Shows that rewards are not the vault asset (BPT) but other tokens.
    function testFastForward(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        vm.warp(block.timestamp + 100 days);

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this) // TODO: confirm that this all works with the Aura Pool of course.

        assertApproxEqAbs(assets, redeemedAssets, 2, "User should have been sent vault assets.");
        assertApproxEqAbs(
            auraRETHWETHBPT.balanceOf(address(this)),
            redeemedAssets,
            2,
            "User should have been sent vault assets."
        );
    }

    // TODO: rewards are going to be handled by other Aura adaptor: `AuraExtrasAdaptor.sol` so this test may not be here. Could have this test just check that we receive the BPTs initially deposited even after a long time. Rewards are in the form of tokens that are not the base asset BPT.
    function testInterestAccrual(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        vm.warp(block.timestamp + 100 days); // fast forward to accrue rewards

        uint256 oldBALRewards = BAL.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)
        uint256 oldAURARewards = AURA.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)
        uint256 oldBPTBalance = rETH_wETH_BPT.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)

        auraExtrasAdaptor.getRewards(IBaseRewardPool(aura_rETH_wETH_BPT), false); // TODO: EIN, check the logs to see what reward tokens are claimed with bool set to false. Then compare to what it is as true.

        assertGt(BAL.balanceOf(address(cellar)), oldBALRewards);
        assertGt(AURA.balanceOf(address(cellar)), oldAURARewards);
        assertEq(rETH_wETH_BPT.balanceOf(address(cellar)), oldBPTBalance); // check that BPT was not brought in when claiming rewards
    }

    function testIntegration(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        vm.warp(block.timestamp + 100 days); // fast forward to accrue rewards

        auraExtrasAdaptor.getRewards(IBaseRewardPool(aura_rETH_wETH_BPT), false); // TODO: EIN, check the logs to see what reward tokens are claimed with bool set to false. Then compare to what it is as true.

        uint256 newBALRewards = BAL.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)
        uint256 newAURARewards = AURA.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)
        uint256 oldBPTBalance = rETH_wETH_BPT.balanceOf(address(cellar)); // TODO: double check whether it is sent to cellar or address(this)

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this) // TODO: confirm that this all works with the Aura Pool of course.

        // check that the rewards haven't changed because of redeem
        assertEq(BAL.balanceOf(address(cellar)), newBALRewards);
        assertEq(AURA.balanceOf(address(cellar)), newAURARewards);
        assertGt(rETH_wETH_BPT.balanceOf(address(cellar)), oldBPTBalance);
    }
}
