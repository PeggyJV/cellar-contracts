// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC4626Adaptor } from "src/modules/adaptors/ERC4626Adaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarWithERC4626AdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    Cellar private usdcCLR;
    Cellar private wethCLR;
    Cellar private wbtcCLR;

    ERC4626Adaptor private erc4626Adaptor;

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
    uint32 private cellarPosition = 8;

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
        erc4626Adaptor = new ERC4626Adaptor();

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

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // WETH Simulated Price: $2000
        // WBTC Simulated Price: $30,000
        mockUsdcUsd.setMockAnswer(1e8);
        mockWethUsd.setMockAnswer(2_000e8);
        mockWbtcUsd.setMockAnswer(30_000e8);
        mockUsdtUsd.setMockAnswer(1e8);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustAdaptor(address(erc4626Adaptor));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(USDT));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        usdcCLR = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);
        vm.label(address(usdcCLR), "usdcCLR");

        cellarName = "Dummy Cellar V0.1";
        initialDeposit = 1e12;
        platformCut = 0.75e18;
        wethCLR = _createCellar(cellarName, WETH, wethPosition, abi.encode(true), initialDeposit, platformCut);
        vm.label(address(wethCLR), "wethCLR");

        cellarName = "Dummy Cellar V0.2";
        initialDeposit = 1e4;
        platformCut = 0.75e18;
        wbtcCLR = _createCellar(cellarName, WBTC, wbtcPosition, abi.encode(true), initialDeposit, platformCut);
        vm.label(address(wbtcCLR), "wbtcCLR");

        // Add Cellar Positions to the registry.
        registry.trustPosition(usdcCLRPosition, address(erc4626Adaptor), abi.encode(usdcCLR));
        registry.trustPosition(wethCLRPosition, address(erc4626Adaptor), abi.encode(wethCLR));
        registry.trustPosition(wbtcCLRPosition, address(erc4626Adaptor), abi.encode(wbtcCLR));

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        // Set up remaining cellar positions.
        cellar.addPositionToCatalogue(usdcCLRPosition);
        cellar.addPosition(1, usdcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethCLRPosition);
        cellar.addPosition(2, wethCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcCLRPosition);
        cellar.addPosition(3, wbtcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(4, wethPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPosition(5, wbtcPosition, abi.encode(true), false);
        cellar.addAdaptorToCatalogue(address(erc4626Adaptor));
        cellar.addPositionToCatalogue(usdtPosition);

        cellar.setStrategistPayoutAddress(strategist);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================== REBALANCE TEST ==========================================

    // In the context of using the ERC4626Adaptor, the cellars are customized ERC4626s, so they should work in a sense with the ERC4626Adaptor. That is what is being tested.
    function testTotalAssets(
        uint256 usdcAmount,
        uint256 usdcCLRAmount,
        uint256 wethCLRAmount,
        uint256 wbtcCLRAmount,
        uint256 wethAmount
    ) external {
        usdcAmount = bound(usdcAmount, 1e6, 1_000_000e6);
        usdcCLRAmount = bound(usdcCLRAmount, 1e6, 1_000_000e6);
        wethCLRAmount = bound(wethCLRAmount, 1e6, 1_000_000e6);
        wbtcCLRAmount = bound(wbtcCLRAmount, 1e6, 1_000_000e6);
        wethAmount = bound(wethAmount, 1e18, 10_000e18);
        uint256 totalAssets = cellar.totalAssets();

        assertEq(totalAssets, initialAssets, "Cellar total assets should be initialAssets.");

        deal(address(USDC), address(this), usdcCLRAmount + wethCLRAmount + wbtcCLRAmount + usdcAmount);
        cellar.deposit(usdcCLRAmount + wethCLRAmount + wbtcCLRAmount + usdcAmount, address(this));

        _depositToVault(cellar, usdcCLR, usdcCLRAmount);
        _depositToVault(cellar, wethCLR, wethCLRAmount);
        _depositToVault(cellar, wbtcCLR, wbtcCLRAmount);
        deal(address(WETH), address(cellar), wethAmount);

        uint256 expectedTotalAssets = usdcAmount +
            usdcCLRAmount +
            priceRouter.getValue(WETH, wethAmount, USDC) +
            wethCLRAmount +
            wbtcCLRAmount +
            initialAssets;

        totalAssets = cellar.totalAssets();

        assertApproxEqRel(
            totalAssets,
            expectedTotalAssets,
            0.0001e18,
            "`totalAssets` should equal all asset values summed together."
        );
    }

    // ====================================== PLATFORM FEE TEST ======================================

    // keep
    function testCellarWithCellarPositions() external {
        // Cellar A's asset is USDC, holding position is Cellar B shares, whose holding asset is USDC.
        // Initialize test Cellars.

        // Create Cellar B
        string memory cellarName = "Cellar B V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;
        Cellar cellarB = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        uint32 cellarBPosition = 10;
        registry.trustPosition(cellarBPosition, address(erc4626Adaptor), abi.encode(cellarB));

        // Create Cellar A
        cellarName = "Cellar A V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        Cellar cellarA = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        cellarA.addPositionToCatalogue(cellarBPosition);
        cellarA.addPosition(0, cellarBPosition, abi.encode(true), false);
        cellarA.setHoldingPosition(cellarBPosition);
        cellarA.swapPositions(0, 1, false);

        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellarA), assets);
        cellarA.deposit(assets, address(this));

        uint256 withdrawAmount = cellarA.maxWithdraw(address(this));
        assertEq(assets, withdrawAmount, "Assets should not have changed.");
        assertEq(cellarA.totalAssets(), cellarB.totalAssets(), "Total assets should be the same.");

        cellarA.withdraw(withdrawAmount, address(this), address(this));
    }

    //============================================ Helper Functions ===========================================

    function _depositToVault(Cellar targetFrom, Cellar targetTo, uint256 amountIn) internal {
        ERC20 assetIn = targetFrom.asset();
        ERC20 assetOut = targetTo.asset();

        uint256 amountTo = priceRouter.getValue(assetIn, amountIn, assetOut);

        // Update targetFrom ERC20 balances.
        deal(address(assetIn), address(targetFrom), assetIn.balanceOf(address(targetFrom)) - amountIn);
        deal(address(assetOut), address(targetFrom), assetOut.balanceOf(address(targetFrom)) + amountTo);

        // Rebalance into targetTo.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToERC4626Vault(address(targetTo), amountTo);
            data[0] = Cellar.AdaptorCall({ adaptor: address(erc4626Adaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        targetFrom.callOnAdaptor(data);
    }

    function testUsingIlliquidCellarPosition() external {
        registry.trustPosition(cellarPosition, address(erc4626Adaptor), abi.encode(address(cellar)));

        string memory cellarName = "Meta Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        Cellar metaCellar = _createCellar(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );
        initialAssets = metaCellar.totalAssets();

        metaCellar.addPositionToCatalogue(cellarPosition);
        metaCellar.addAdaptorToCatalogue(address(erc4626Adaptor));
        metaCellar.addPosition(0, cellarPosition, abi.encode(false), false);
        metaCellar.setHoldingPosition(cellarPosition);

        USDC.safeApprove(address(metaCellar), type(uint256).max);

        // Deposit into meta cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);

        metaCellar.deposit(assets, address(this));

        uint256 assetsDeposited = cellar.totalAssets();
        assertEq(assetsDeposited, assets + initialAssets, "All assets should have been deposited into cellar.");

        uint256 liquidAssets = metaCellar.maxWithdraw(address(this));
        assertEq(
            liquidAssets,
            initialAssets,
            "Meta Cellar only liquid assets should be USDC deposited in constructor."
        );

        // Check logic in the withdraw function by having strategist call withdraw, passing in isLiquid = false.
        bool isLiquid = false;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            ERC4626Adaptor.withdraw.selector,
            assets,
            address(this),
            abi.encode(cellar),
            abi.encode(isLiquid)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(erc4626Adaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        metaCellar.callOnAdaptor(data);
    }
}
