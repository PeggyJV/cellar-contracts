// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { IVault, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { AuraERC4626Adaptor } from "src/modules/adaptors/Aura/AuraERC4626Adaptor.sol";

/**
 * @title AuraERC4626AdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Aura BPT Pools
 * @dev Mock datafeeds to be used for underlying BPTs. For tests, we'll go with rETH / wETH BPT pair. We'll use mock datafeeds for the constituent assets of this pair so we can warp forward to simulate reward accrual.
 * NOTE: transferrance of aura-wrapped BPT is not alowed as per their contracts
 */
contract AuraERC4626AdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AuraERC4626Adaptor private auraERC4626Adaptor;

    ERC4626 public auraRETHWETHBPTVault = ERC4626(address(aura_rETH_wETH_BPT));
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
    uint32 private auraExtras_RETH_WETH_BPT_Position = 7;

    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18172424;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        auraERC4626Adaptor = new AuraERC4626Adaptor();

        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, IVault(vault));
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockRethUsd = new MockDataFeed(RETH_ETH_FEED);

        uint256 price = uint256(IChainlinkAggregator(address(mockWethUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockRethUsd)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockRethUsd));
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(BAL_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BAL_USD_FEED);
        priceRouter.addAsset(BAL, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(AURA, settings, abi.encode(stor), price);

        // Add rETH_wETH_BPT pricing.
        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
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
        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(extensionStor), 168726469843); // obtained via local testing in terminal

        mockWethUsd.setMockUpdatedAt(block.timestamp);
        mockRethUsd.setMockUpdatedAt(block.timestamp);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(auraERC4626Adaptor));

        registry.trustPosition(rETH_wETH_BPT_Position, address(erc20Adaptor), abi.encode(rETH_wETH_BPT));
        registry.trustPosition(balPosition, address(erc20Adaptor), abi.encode(BAL));
        registry.trustPosition(auraPosition, address(erc20Adaptor), abi.encode(AURA));
        registry.trustPosition(
            auraRethWethBptPoolPosition,
            address(auraERC4626Adaptor),
            abi.encode(address(aura_rETH_wETH_BPT))
        );

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

        cellar.addAdaptorToCatalogue(address(auraERC4626Adaptor));
        cellar.addPositionToCatalogue(auraRethWethBptPoolPosition); // auraERC4626 for rETH_wETH_BPT

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

        uint256 assetsInAuraPool = auraRETHWETHBPTVault.balanceOf(address(cellar)); // as per Aura BaseRewardPool4626.sol - this is ASSUMING 1:1 for BPT (vault asset) : AuraBPT (shareToken)
        // It is seen in the auraPool code that balanceOf() is overridden: ie. function balanceOf(address account) public view override(BaseRewardPool, IERC20) --> this means that it just reports how much `asset` (aka BPT) is in the auraPool for the user.

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
        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this)

        assertApproxEqAbs(
            assets,
            redeemedAssets,
            2,
            "Time passing should not change the amount of BPTs sent to user unless strategist loops rewards to buy more BPTs or something else."
        );
        assertApproxEqAbs(
            rETH_wETH_BPT.balanceOf(address(this)),
            assets,
            1,
            "All BPTs should have been returned to user."
        );
        assertApproxEqAbs(
            auraRETHWETHBPTVault.balanceOf(address(cellar)),
            0,
            2,
            "Cellar should have redeemed all vault aura share tokens."
        );
    }

    // same as redeem test but with a long time within the vault. Shows that rewards are not the vault asset (BPT) but other tokens.
    function testFastForward(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        skip(100 days);
        mockWethUsd.setMockUpdatedAt(block.timestamp);
        mockRethUsd.setMockUpdatedAt(block.timestamp);

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this)

        assertApproxEqAbs(
            assets,
            redeemedAssets,
            2,
            "BPT balance should not change, yield is earned via other ERC20s (AURA, BAL, etc.)."
        );
        assertApproxEqAbs(
            rETH_wETH_BPT.balanceOf(address(this)),
            assets,
            1,
            "All BPTs should have been returned to user."
        );
        assertApproxEqAbs(
            auraRETHWETHBPTVault.balanceOf(address(cellar)),
            0,
            2,
            "Cellar should have redeemed all vault aura share tokens."
        );
    }

    function testInterestAccrual(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);

        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        vm.warp(block.timestamp + 100 days); // fast forward to accrue rewards
        mockWethUsd.setMockUpdatedAt(block.timestamp);
        mockRethUsd.setMockUpdatedAt(block.timestamp);

        uint256 oldBALRewards = BAL.balanceOf(address(cellar));
        uint256 oldAURARewards = AURA.balanceOf(address(cellar));
        uint256 oldBPTBalance = rETH_wETH_BPT.balanceOf(address(cellar));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bool claimExtras = true;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataGetRewardsFromAuraPoolERC4626(address(aura_rETH_wETH_BPT), claimExtras);
            data[0] = Cellar.AdaptorCall({ adaptor: address(auraERC4626Adaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data); 

        assertGt(BAL.balanceOf(address(cellar)), oldBALRewards);
        assertGt(AURA.balanceOf(address(cellar)), oldAURARewards);
        assertEq(rETH_wETH_BPT.balanceOf(address(cellar)), oldBPTBalance); // check that BPT was not brought in when claiming rewards
    }

    function testIntegration(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000_000e18);
        deal(address(rETH_wETH_BPT), address(this), assets);
        cellar.deposit(assets, address(this)); // bpts sent to aura pool as seen in deposit() tests

        vm.warp(block.timestamp + 100 days); // fast forward to accrue rewards
        mockWethUsd.setMockUpdatedAt(block.timestamp);
        mockRethUsd.setMockUpdatedAt(block.timestamp);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bool claimExtras = true;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataGetRewardsFromAuraPoolERC4626(address(aura_rETH_wETH_BPT), claimExtras);
            data[0] = Cellar.AdaptorCall({ adaptor: address(auraERC4626Adaptor), callData: adaptorCalls });
        }

        uint256 newBALRewards = BAL.balanceOf(address(cellar));
        uint256 newAURARewards = AURA.balanceOf(address(cellar));

        uint256 maxRedeem = cellar.maxRedeem(address(this));

        uint256 redeemedAssets = cellar.redeem(maxRedeem, address(this), address(this)); // state mutative call to redeem assets to address(this)

        // check that the rewards haven't changed because of redeem
        assertEq(BAL.balanceOf(address(cellar)), newBALRewards);
        assertEq(AURA.balanceOf(address(cellar)), newAURARewards);
        assertEq(rETH_wETH_BPT.balanceOf(address(cellar)), initialAssets);
        assertEq(rETH_wETH_BPT.balanceOf(address(this)), assets);
        assertApproxEqAbs(
            assets,
            redeemedAssets,
            2,
            "Time passing should not change the amount of BPTs sent to user unless strategist loops rewards to buy more BPTs or something else."
        );
    }
}
