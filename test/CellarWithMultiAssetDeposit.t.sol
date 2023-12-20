// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { CellarWithMultiAssetDeposit } from "src/base/permutations/CellarWithMultiAssetDeposit.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarWithMultiAssetDepositTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    CellarWithMultiAssetDeposit private cellar;

    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockWbtcUsd;
    MockDataFeed private mockUsdtUsd;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private usdcCLRPosition = 4;
    uint32 private wethCLRPosition = 5;
    uint32 private wbtcCLRPosition = 6;
    uint32 private usdtPosition = 7;

    uint256 private initialAssets;
    uint256 private initialShares;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);
        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockWbtcUsd = new MockDataFeed(WBTC_USD_FEED);
        mockUsdtUsd = new MockDataFeed(USDT_USD_FEED);

        // Set mock stable coin feeds to $1.
        // mockUsdcUsd.setMockAnswer(1e8);
        // mockUsdtUsd.setMockAnswer(1e8);

        // Setup pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(mockUsdcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);
        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);
        price = uint256(mockWbtcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWbtcUsd));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);
        price = uint256(mockUsdtUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdtUsd));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(USDT));

        string memory cellarName = "Cellar V0.0";
        uint256 initialDeposit = 1e6;
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(0xa0Cb889707d426A7A386870A03bc70d1b0697598, initialDeposit);
        uint64 platformCut = 0.75e18;
        cellar = new CellarWithMultiAssetDeposit(
            address(this),
            registry,
            USDC,
            cellarName,
            "POG",
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        // Set up remaining cellar positions.
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(0, wethPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPosition(0, wbtcPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(usdtPosition);
        cellar.addPosition(0, usdtPosition, abi.encode(true), false);

        cellar.setStrategistPayoutAddress(strategist);
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");
        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================= HAPPY PATH TEST =========================================

    // Can we accept the Curve LP tokens? I dont see why not.

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);

        deal(address(USDC), address(this), assets);
        USDC.safeApprove(address(cellar), assets);

        cellar.deposit(assets, address(this));

        assertEq(
            cellar.totalAssets(),
            initialAssets + assets,
            "Cellar totalAssets should equal initial + new deposit."
        );
        assertEq(
            cellar.totalSupply(),
            initialAssets + assets,
            "Cellar totalSupply should equal initial + new deposit."
        ); // Because share price is 1:1.
    }

    function testDepositWithAlternativeAsset(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);

        // Setup Cellar to accept USDT deposits.
        cellar.setAlternativeAssetData(USDT, usdtPosition, 0);

        deal(address(USDT), address(this), assets);
        USDT.safeApprove(address(cellar), assets);

        bytes memory depositCallData = abi.encodeWithSelector(Cellar.deposit.selector, assets, address(this), USDT);

        address(cellar).functionCall(depositCallData);

        // Since share price is 1:1, and USDT is hardcoded to equal the same as USDC, below checks should pass.
        assertEq(cellar.previewRedeem(1e6), 1e6, "Cellar share price should be 1.");

        cellar.dropAlternativeAssetData(USDT);

        // address(cellar).functionCall(depositCallData);
    }

    function testDepositWithAlternativeAssetSameAsBase(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);

        // Setup Cellar to accept USDT deposits.
        cellar.setAlternativeAssetData(USDC, usdcPosition, 0);

        deal(address(USDC), address(this), assets);
        USDC.safeApprove(address(cellar), assets);

        bytes memory depositCallData = abi.encodeWithSelector(Cellar.deposit.selector, assets, address(this), USDC);

        address(cellar).functionCall(depositCallData);

        // Since share price is 1:1, and USDT is hardcoded to equal the same as USDC, below checks should pass.
        assertEq(
            cellar.totalAssets(),
            initialAssets + assets,
            "Cellar totalAssets should equal initial + new deposit."
        );
        assertEq(
            cellar.totalSupply(),
            initialAssets + assets,
            "Cellar totalSupply should equal initial + new deposit."
        );
    }

    // TODO check for reverts.

    function testAlternativeAssetFeeLogic(uint256 assets, uint32 fee) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);
        fee = uint32(bound(fee, 0, 0.1e8));

        address user = vm.addr(777);
        deal(address(USDT), user, assets);

        // Setup Cellar to accept USDT deposits.
        cellar.setAlternativeAssetData(USDT, usdtPosition, fee);

        vm.startPrank(user);

        USDT.safeApprove(address(cellar), assets);

        bytes memory depositCallData = abi.encodeWithSelector(Cellar.deposit.selector, assets, user, USDT);

        address(cellar).functionCall(depositCallData);

        vm.stopPrank();

        uint256 assetsIn = priceRouter.getValue(USDT, assets, USDC);
        uint256 assetsInWithFee = assetsIn.mulDivDown(1e8 - fee, 1e8);

        uint256 expectedShares = cellar.previewDeposit(assetsInWithFee);

        uint256 userShareBalance = cellar.balanceOf(user);

        assertApproxEqAbs(userShareBalance, expectedShares, 1, "User shares should equal expected.");

        uint256 expectedSharePrice = (initialAssets + assetsIn).mulDivDown(1e6, cellar.totalSupply());

        // Since share price is 1:1, and USDT is hardcoded to equal the same as USDC, below checks should pass.
        assertApproxEqAbs(
            cellar.previewRedeem(1e6),
            expectedSharePrice,
            1,
            "Cellar share price should be equal expected."
        );

        assertLe(
            cellar.previewRedeem(userShareBalance),
            assetsInWithFee,
            "User preview redeem should under estimate or equal."
        );

        assertApproxEqRel(
            cellar.previewRedeem(userShareBalance),
            assetsInWithFee,
            0.000002e18,
            "User preview redeem should equal assets in with fee."
        );
    }
}
