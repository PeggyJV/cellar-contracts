// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { CellarWithMultiAssetDeposit } from "src/base/permutations/CellarWithMultiAssetDeposit.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";

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

        cellar.multiAssetDeposit(USDT, assets, address(this));

        // Since share price is 1:1, below checks should pass.
        assertEq(cellar.previewRedeem(1e6), 1e6, "Cellar share price should be 1.");
    }

    function testDepositWithAlternativeAssetSameAsBase(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);

        // Setup Cellar to accept USDC deposits.
        cellar.setAlternativeAssetData(USDC, usdcPosition, 0);

        deal(address(USDC), address(this), assets);
        USDC.safeApprove(address(cellar), assets);

        cellar.multiAssetDeposit(USDC, assets, address(this));

        // Since share price is 1:1, below checks should pass.
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

    function testAlternativeAssetFeeLogic(uint256 assets, uint32 fee) external {
        assets = bound(assets, 1e6, 1_000_000_000e6);
        fee = uint32(bound(fee, 0, 0.1e8));

        address user = vm.addr(777);
        deal(address(USDT), user, assets);

        // Setup Cellar to accept USDT deposits.
        cellar.setAlternativeAssetData(USDT, usdtPosition, fee);

        uint256 expectedShares = cellar.previewMultiAssetDeposit(USDT, assets);

        vm.startPrank(user);
        USDT.safeApprove(address(cellar), assets);
        cellar.multiAssetDeposit(USDT, assets, user);
        vm.stopPrank();

        // Check preview logic.
        uint256 userShareBalance = cellar.balanceOf(user);
        assertApproxEqAbs(userShareBalance, expectedShares, 1, "User shares should equal expected.");

        uint256 assetsIn = priceRouter.getValue(USDT, assets, USDC);
        uint256 assetsInWithFee = assetsIn.mulDivDown(1e8 - fee, 1e8);
        uint256 expectedSharePrice = (initialAssets + assetsIn).mulDivDown(1e6, cellar.totalSupply());

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

    function testDroppingAnAlternativeAsset() external {
        uint256 assets = 100e6;

        cellar.setAlternativeAssetData(USDT, usdtPosition, 0);

        deal(address(USDT), address(this), assets);
        USDT.safeApprove(address(cellar), assets);

        cellar.multiAssetDeposit(USDT, assets, address(this));

        // But if USDT is dropped, deposits revert.
        cellar.dropAlternativeAssetData(USDT);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CellarWithMultiAssetDeposit.CellarWithMultiAssetDeposit__AlternativeAssetNotSupported.selector
                )
            )
        );
        cellar.multiAssetDeposit(USDT, assets, address(this));

        (bool isSupported, uint32 holdingPosition, uint32 fee) = cellar.alternativeAssetData(USDT);
        assertEq(isSupported, false, "USDT should not be supported.");
        assertEq(holdingPosition, 0, "Holding position should be zero.");
        assertEq(fee, 0, "Fee should be zero.");
    }

    function testSettingAlternativeAssetDataAgain() external {
        cellar.setAlternativeAssetData(USDT, usdtPosition, 0);

        // Owner decides they actually want to add a fee.
        cellar.setAlternativeAssetData(USDT, usdtPosition, 0.0010e8);

        (bool isSupported, uint32 holdingPosition, uint32 fee) = cellar.alternativeAssetData(USDT);
        assertEq(isSupported, true, "USDT should be supported.");
        assertEq(holdingPosition, usdtPosition, "Holding position should be usdt position.");
        assertEq(fee, 0.0010e8, "Fee should be 10 bps.");
    }

    // ======================== Test Reverts ==========================
    function testDepositReverts() external {
        uint256 assets = 100e6;

        deal(address(USDT), address(this), assets);
        USDT.safeApprove(address(cellar), assets);

        // Try depositing with an asset that is not setup.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CellarWithMultiAssetDeposit.CellarWithMultiAssetDeposit__AlternativeAssetNotSupported.selector
                )
            )
        );
        cellar.multiAssetDeposit(USDT, assets, address(this));
    }

    function testOwnerReverts() external {
        // Owner tries to setup cellar to accept alternative deposits but messes up the inputs.

        // Tries setting up using a holding position not used by the cellar.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionNotUsed.selector, wbtcPosition)));
        cellar.setAlternativeAssetData(WBTC, wbtcPosition, 0);

        // setting up but with a mismatched underlying and position.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__AssetMismatch.selector, USDC, USDT)));
        cellar.setAlternativeAssetData(USDC, usdtPosition, 0);

        // Setting up a debt holding position.
        uint32 debtWethPosition = 8;
        ERC20DebtAdaptor debtAdaptor = new ERC20DebtAdaptor();
        registry.trustAdaptor(address(debtAdaptor));
        registry.trustPosition(debtWethPosition, address(debtAdaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(debtWethPosition);
        cellar.addPosition(0, debtWethPosition, abi.encode(0), true);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidHoldingPosition.selector, debtWethPosition))
        );
        cellar.setAlternativeAssetData(WETH, debtWethPosition, 0);

        // Tries setting fee to be too large.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CellarWithMultiAssetDeposit.CellarWithMultiAssetDeposit__AlternativeAssetFeeTooLarge.selector
                )
            )
        );
        cellar.setAlternativeAssetData(USDT, usdtPosition, 0.10000001e8);
    }
}
