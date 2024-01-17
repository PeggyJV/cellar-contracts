// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract ERC20AdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    Cellar private cellar;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16921343;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        string memory cellarName = "ERC20 Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        cellar.addPositionToCatalogue(wethPosition);

        cellar.setRebalanceDeviation(0.01e18);

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testLogic(uint256 assets, uint256 illiquidMultiplier) external {
        assets = bound(assets, 1e6, 1_000_000e6);
        illiquidMultiplier = bound(illiquidMultiplier, 0, 1e18); // The percent of assets that are illiquid in the cellar.

        // USDC is liquid, but WETH is not liquid.
        cellar.addPosition(1, wethPosition, abi.encode(false), false);

        // Have user deposit into cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 totalAssets = cellar.totalAssets();
        assertEq(totalAssets, assets + initialAssets, "All assets should be accounted for.");
        // All assets should be liquid.
        uint256 liquidAssets = cellar.totalAssetsWithdrawable();
        assertEq(liquidAssets, totalAssets, "All assets should be liquid.");

        // Simulate a strategist rebalance into WETH.
        uint256 assetsIlliquid = assets.mulDivDown(illiquidMultiplier, 1e18);
        uint256 assetsInWeth = priceRouter.getValue(USDC, assetsIlliquid, WETH);
        deal(address(USDC), address(cellar), totalAssets - assetsIlliquid);
        deal(address(WETH), address(cellar), assetsInWeth);

        totalAssets = cellar.totalAssets();
        assertApproxEqAbs(totalAssets, assets + initialAssets, 1, "Total assets should be the same.");

        liquidAssets = cellar.totalAssetsWithdrawable();
        assertApproxEqAbs(liquidAssets, totalAssets - assetsIlliquid, 1, "Cellar should only be partially liquid.");

        // If for some reason a cellar tried to pull from the illiquid position it would revert.
        bytes memory data = abi.encodeWithSelector(
            ERC20Adaptor.withdraw.selector,
            1,
            address(this),
            abi.encode(WETH),
            abi.encode(false)
        );

        vm.startPrank(address(cellar));
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        address(erc20Adaptor).functionDelegateCall(data);
        vm.stopPrank();
    }
}
