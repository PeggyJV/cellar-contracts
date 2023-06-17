// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SafeTransferLib } from "src/base/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarCompoundTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CTokenAdaptor private cTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    VestingSimpleAdaptor private vestingAdaptor;
    VestingSimple private vesting;
    MockCellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;

    address private immutable strategist = vm.addr(0xBEEF);

    ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    CErc20 private cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    CErc20 private cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    ERC20 private TUSD = ERC20(0x0000000000085d4780B73119b644AE5ecd22b376);
    CErc20 private cTUSD = CErc20(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address private TUSD_USD_FEED = 0xec746eCF986E2927Abd291a2A1716c940100f8Ba;

    uint32 private daiPosition;
    uint32 private cDAIPosition;
    uint32 private usdcPosition;
    uint32 private cUSDCPosition;
    uint32 private daiVestingPosition;

    function setUp() external {
        vesting = new VestingSimple(USDC, 1 days / 4, 1e6);
        cTokenAdaptor = new CTokenAdaptor(address(comptroller), address(COMP));
        erc20Adaptor = new ERC20Adaptor();
        vestingAdaptor = new VestingSimpleAdaptor();
        priceRouter = new PriceRouter(registry, WETH);
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor(uniV2Router, uniV3Router);
        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](5);
        uint32[] memory debtPositions;
        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(cTokenAdaptor));
        registry.trustAdaptor(address(vestingAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));

        daiPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI));
        cDAIPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(cDAI));
        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        cUSDCPosition = registry.trustPosition(address(cTokenAdaptor), abi.encode(cUSDC));
        daiVestingPosition = registry.trustPosition(address(vestingAdaptor), abi.encode(vesting));
        positions[0] = cDAIPosition;
        positions[1] = daiPosition;
        positions[2] = cUSDCPosition;
        positions[3] = usdcPosition;
        positions[4] = daiVestingPosition;
        bytes[] memory positionConfigs = new bytes[](5);
        bytes[] memory debtConfigs;
        cellar = new MockCellar(
            registry,
            DAI,
            "Compound Lending Cellar",
            "COMP-CLR",
            abi.encode(positions, debtPositions, positionConfigs, debtConfigs, cDAIPosition, address(0))
        );
        cellar.setRebalanceDeviation(0.003e18);
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        DAI.safeApprove(address(cellar), type(uint256).max);
        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit() external {
        uint256 assets = 100e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cDAI.balanceOf(address(cellar)).mulDivDown(cDAI.exchangeRateStored(), 1e18),
            assets,
            0.001e18,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw() external {
        uint256 assets = 100e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(DAI), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(DAI.balanceOf(address(this)), amountToWithdraw, "Amount withdrawn should equal callers DAI balance.");
    }

    function testTotalAssets() external {
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(cellar.totalAssets(), assets, 0.0002e18, "Total assets should equal assets deposited.");

        // Swap from DAI to USDC and lend USDC on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(cDAI, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(DAI, USDC, 100, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(cUSDC, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Account for 0.1% Swap Fee.
        assets = assets - assets.mulDivDown(0.001e18, 2e18);
        // Make sure Total Assets is reasonable.
        assertApproxEqRel(
            cellar.totalAssets(),
            assets,
            0.001e18,
            "Total assets should equal assets deposited minus swap fees."
        );
    }

    function testClaimCompAndVest() external {
        uint256 assets = 10_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Manipulate Comptroller storage to give Cellar some pending COMP.
        uint256 compReward = 10e18;
        stdstore
            .target(address(comptroller))
            .sig(comptroller.compAccrued.selector)
            .with_key(address(cellar))
            .checked_write(compReward);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Create data to claim COMP and swap it for USDC.
        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = address(WETH);
        path[2] = address(USDC);
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 500;
        bytes memory params = abi.encode(path, poolFees, 0, 0);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                SwapWithUniswapAdaptor.swapWithUniV3.selector,
                path,
                poolFees,
                type(uint256).max,
                0
            );
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            // Create data to vest USDC.
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.depositToVesting.selector,
                vesting,
                type(uint256).max
            );
            data[2] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 totalAssets = cellar.totalAssets();

        // Pass time to fully vest the USDC.
        vm.warp(block.timestamp + 1 days / 4);

        assertApproxEqRel(
            cellar.totalAssets(),
            totalAssets + priceRouter.getValue(COMP, compReward, USDC),
            0.05e18,
            "New totalAssets should equal previous plus vested USDC."
        );
    }

    function testMaliciousStrategistMovingFundsIntoUntrackedCompoundPosition() external {
        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBeforeAttack = cellar.totalAssets();

        // Strategist malicously makes several `callOnAdaptor` calls to lower the Cellars Share Price.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint256 amountToLend = assets;
        for (uint8 i; i < 10; i++) {
            // Choose a value close to the Cellars rebalance deviation limit.
            amountToLend = cellar.totalAssets().mulDivDown(0.003e18, 1e18);
            adaptorCalls[0] = _createBytesDataToLend(cDAI, amountToLend);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }
        uint256 assetsLost = assetsBeforeAttack - cellar.totalAssets();
        assertApproxEqRel(
            assetsLost,
            assets.mulDivDown(0.03e18, 1e18),
            0.02e18,
            "Assets Lost should be about 3% of original TVL."
        );

        // Somm Governance sees suspicious rebalances, and temporarily shuts down the cellar.
        cellar.initiateShutdown();

        // Somm Governance revokes old strategists privilages and puts in new strategist.

        // Shut down is lifted, and strategist rebalances cellar back to original value.
        cellar.liftShutdown();
        uint256 amountToWithdraw = assetsLost / 12;
        for (uint8 i; i < 12; i++) {
            adaptorCalls[0] = _createBytesDataToWithdraw(cDAI, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertApproxEqRel(cellar.totalAssets(), assets, 0.001e18, "totalAssets should be equal to original assets.");
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(TUSD)))
        );
        registry.trustPosition(address(cTokenAdaptor), abi.encode(address(cTUSD)));

        // Add TUSD.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(TUSD_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, TUSD_USD_FEED);
        priceRouter.addAsset(TUSD, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(address(cTokenAdaptor), abi.encode(address(cTUSD)));
    }

    function testErrorCodeCheck() external {
        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Convert cellar assets to USDC.
        assets = assets.changeDecimals(18, 6);
        deal(address(DAI), address(cellar), 0);
        deal(address(USDC), address(cellar), assets);

        // Strategist tries to lend more USDC then they have,
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Choose an amount too large so deposit fails.
        uint256 amountToLend = assets + 1;

        adaptorCalls[0] = _createBytesDataToLend(cUSDC, amountToLend);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 13))
        );
        cellar.callOnAdaptor(data);

        // Strategist tries to withdraw more assets then they have.
        adaptorCalls = new bytes[](2);
        amountToLend = assets;
        uint256 amountToWithdraw = assets + 1e6;

        adaptorCalls[0] = _createBytesDataToLend(cUSDC, amountToLend);
        adaptorCalls[1] = _createBytesDataToWithdraw(cUSDC, amountToWithdraw);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _createBytesDataForSwap(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    }

    function _createBytesDataToLend(CErc20 market, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
    }

    function _createBytesDataToWithdraw(CErc20 market, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
    }

    function _createBytesDataToClaimComp() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
    }
}
