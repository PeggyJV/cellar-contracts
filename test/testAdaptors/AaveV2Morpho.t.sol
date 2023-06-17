// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { MorphoAaveV2ATokenAdaptor, IMorphoV2, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/WstEthExtension.sol";
import { IPoolV3 } from "src/interfaces/external/IPoolV3.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IMorphoLensV2 } from "src/interfaces/external/Morpho/IMorphoLensV2.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveV2MorphoTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    MorphoAaveV2ATokenAdaptor private aTokenAdaptor;
    MorphoAaveV2DebtTokenAdaptor private debtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;
    OneInchAdaptor private oneInchAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Aave V2 positions.
    address public aSTETH = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address public aWETH = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    address public aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address public aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address public dWETH = 0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf;

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IPoolV3 private pool = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    IMorphoV2 private morpho = IMorphoV2(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
    address private morphoLens = 0x507fA343d0A90786d86C7cd885f5C49263A91FF4;
    address private rewardHandler = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    WstEthExtension private wstEthOracle;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;

    address private aWstEthWhale = 0xAF06acFD1BD492B913d5807d562e4FC3A6343C4E;

    uint32 private wethPosition;
    uint32 private usdcPosition;
    uint32 private stethPosition;
    uint32 private morphoAWethPosition;
    uint32 private morphoAUsdcPosition;
    uint32 private morphoAStEthPosition;
    uint32 private morphoDebtWethPosition;

    bytes swapWethToStEth =
        hex"d805a657000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe8400000000000000000000000000000000000000000000002c73c937742c5000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000026812aa3caf0000000000000000000000001136b25047e142fa3018184793aec68fbb173ce4000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000001136b25047e142fa3018184793aec68fbb173ce400000000000000000000000003A6a84cD762D9707A21605b548aaaB891562aAb00000000000000000000000000000000000000000000002c73c937742c50000000000000000000000000000000000000000000000000002c01fcf6e6361bffff000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dc0000000000000000000000000000000000000000be00009000007600003c4101c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200042e1a7d4d00000000000000000000000000000000000000000000000000000000000000004060ae7ab96520de3a18e5e111b5eaab095312d7fe84a1903eab00000000000000000000000042f527f50f16a103b6ccab48bccca214500c10210020d6bdbf78ae7ab96520de3a18e5e111b5eaab095312d7fe8480a06c4eca27ae7ab96520de3a18e5e111b5eaab095312d7fe841111111254eeb25477b68fb85ed929f73a96058200000000cfee7c08000000000000000000000000000000000000000000000000";

    modifier checkBlockNumber() {
        if (block.number < 16869780) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16869780.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        aTokenAdaptor = new MorphoAaveV2ATokenAdaptor(address(morpho), morphoLens, 1.05e18, rewardHandler);
        debtTokenAdaptor = new MorphoAaveV2DebtTokenAdaptor(address(morpho), morphoLens, 1.05e18);
        erc20Adaptor = new ERC20Adaptor();
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor();
        oneInchAdaptor = new OneInchAdaptor();

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));
        priceRouter = new PriceRouter(registry);
        registry.setAddress(2, address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(aTokenAdaptor));
        registry.trustAdaptor(address(debtTokenAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));
        registry.trustAdaptor(address(oneInchAdaptor));

        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        stethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(STETH));
        morphoAWethPosition = registry.trustPosition(address(aTokenAdaptor), abi.encode(aWETH));
        morphoAUsdcPosition = registry.trustPosition(address(aTokenAdaptor), abi.encode(aUSDC));
        morphoAStEthPosition = registry.trustPosition(address(aTokenAdaptor), abi.encode(aSTETH));
        morphoDebtWethPosition = registry.trustPosition(address(debtTokenAdaptor), abi.encode(aWETH));

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                WETH,
                "MORPHO Debt Cellar",
                "MORPHO-CLR",
                morphoAWethPosition,
                abi.encode(0),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(aTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(debtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(stethPosition);
        cellar.addPositionToCatalogue(morphoAWethPosition);
        cellar.addPositionToCatalogue(morphoAStEthPosition);
        cellar.addPositionToCatalogue(morphoDebtWethPosition);

        // cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        // cellar.addPosition(0, wethPosition, abi.encode(0), false);

        WETH.safeApprove(address(cellar), type(uint256).max);

        // UniV2 WETH/STETH slippage is turbo bad, so set a large rebalance deviation.
        cellar.setRebalanceDeviation(0.1e18);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.01e18, 10_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdraw(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.01e18, 10_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Only withdraw assets - 1 because p2pSupplyIndex is not updated, so it is possible
        // for totalAssets to equal assets - 1.
        cellar.withdraw(assets - 1, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.01e18, 10_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 1, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, STETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 3;
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        uint256 balanceInUnderlying = getMorphoDebt(aWETH, address(cellar));

        assertApproxEqAbs(balanceInUnderlying, assets / 3, 1, "WETH debt should equal assets / 3.");
        // Below assert uses such a large range bc of uniV2 slippage.
        assertApproxEqRel(cellar.totalAssets(), assets, 0.90e18, "Total assets should equal assets.");
    }

    function testRepayingLoans(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, STETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        uint256 wethDebt = getMorphoDebt(aWETH, address(cellar));

        assertApproxEqAbs(wethDebt, assets / 4, 1, "WETH debt should equal assets / 4.");

        // Now repay half the debt.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToRepay = wethDebt / 2;
            adaptorCalls[0] = _createBytesDataToRepay(aWETH, wethToRepay);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        wethDebt = getMorphoDebt(aWETH, address(cellar));

        assertApproxEqAbs(wethDebt, assets / 8, 1, "WETH debt should equal assets / 8.");
    }

    function testWithdrawalLogic(uint256 assetsToBorrow) external checkBlockNumber {
        assetsToBorrow = bound(assetsToBorrow, 1, 1_000e18);

        uint256 assetsWithdrawable;
        // Add vanilla WETH to the cellar.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        // Add debt position to cellar.
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        uint256 assetsToLend = 2 * assetsToBorrow;

        deal(address(WETH), address(this), assetsToLend);
        cellar.deposit(assetsToLend, address(this));

        assertTrue(!aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should not be borrowing.");

        // Withdrawable assets should equal assetsToLend.
        assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertApproxEqAbs(assetsWithdrawable, assetsToLend, 1, "Cellar should be fully liquid.");

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, assetsToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        deal(address(WETH), address(cellar), assetsToBorrow + 1);

        assertTrue(aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should be borrowing.");

        // Withdrawable assets should equal assetsToBorrow.
        assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertApproxEqAbs(assetsWithdrawable, assetsToBorrow, 1, "Cellar aToken position should be illiquid.");

        // Rebalance Cellar to repay debt in full.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepay(address(aWETH), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertTrue(!aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should not be borrowing.");

        // Withdrawable assets should equal assetsToLend.
        assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertApproxEqAbs(assetsWithdrawable, assetsToLend, 2, "Cellar should be fully liquid.");
    }

    function testTakingOutLoansInUntrackedPosition(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);
        cellar.removePosition(0, true);

        assets = bound(assets, 0.01e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for STETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, STETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply STETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor reverts because WETH debt is not tracked.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoAaveV2DebtTokenAdaptor.MorphoAaveV2DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(aWETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingDebtThatIsNotOwed(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToRepay = 1;
            adaptorCalls[0] = _createBytesDataToRepay(address(aWETH), wethToRepay);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor fails because the cellar has no WETH debt.
        vm.expectRevert();
        cellar.callOnAdaptor(data);
    }

    function testBlockExternalReceiver(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance into both collateral and p2p.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Supply WETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aWETH, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Strategist tries calling withdraw on collateral.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdraw.selector,
                1,
                strategist,
                abi.encode(aWETH),
                abi.encode(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__ExternalReceiverBlocked.selector)));
        cellar.callOnAdaptor(data);
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegrationRealYieldUsd(uint256 assets) external checkBlockNumber {
        // Create a new cellar that runs the following strategy.
        // Allows for user direct deposit to morpho.
        // Allows for user direct withdraw form morpho.
        // Allows for strategist deposit to morpho.
        // Allows for strategist withdraw form morpho.
        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                USDC,
                "MORPHO P2P Cellar",
                "MORPHO-CLR",
                morphoAUsdcPosition,
                abi.encode(true),
                strategist
            )
        );

        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        cellar.addAdaptorToCatalogue(address(aTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPosition(0, usdcPosition, abi.encode(0), false);

        // assets = 100_000e6;
        assets = bound(assets, 1e6, 1_000_000e6);

        address user = vm.addr(7654);
        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        // Check that users funds where deposited into morpho.
        uint256 assetsInMorpho = getMorphoBalance(aUSDC, address(cellar));
        assertApproxEqAbs(assetsInMorpho, assets, 1, "Assets should have been deposited into Morpho.");

        // Now make sure users can withdraw from morpho.
        deal(address(USDC), user, 0);
        vm.prank(user);
        cellar.withdraw(assetsInMorpho, user, user);

        assertEq(USDC.balanceOf(user), assetsInMorpho, "User should have received assets in morpho.");

        assetsInMorpho = getMorphoBalance(aUSDC, address(cellar));
        assertApproxEqAbs(assetsInMorpho, 0, 1, "Assets should have been withdrawn from morpho.");

        // Strategist changes holding position to be vanilla USDC, so they can try depositing into morpho.
        cellar.setHoldingPosition(usdcPosition);

        // User deposits again.
        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        assertApproxEqAbs(USDC.balanceOf(address(cellar)), assets, 1, "Cellar should be holding assets in USDC.");

        // Strategist rebalances assets into morpho.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Supply USDC as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aUSDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Strategist rebalances assets out of morpho.
        data = new Cellar.AdaptorCall[](1);
        // Supply USDC as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(aUSDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        assertApproxEqAbs(USDC.balanceOf(address(cellar)), assets, 1, "Cellar should be holding USDC.");
    }

    function testIntegrationRealYieldEth(uint256 assets) external checkBlockNumber {
        // Setup cellar so that aSTETH is illiquid.
        // Then have strategist loop into STETH.
        // -Deposit STETH as collateral, and borrow WETH, repeat.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        cellar.addPosition(0, stethPosition, abi.encode(0), false);
        cellar.addPosition(0, morphoAStEthPosition, abi.encode(false), false);
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        // Change holding position to vanilla WETH.
        cellar.setHoldingPosition(wethPosition);

        // Remove unused aWETH Morpho position from the cellar.
        cellar.removePosition(3, false);

        assets = 10e18;
        // assets = bound(assets, 1e18, 100e18);

        address user = vm.addr(7654);
        deal(address(WETH), user, assets);
        vm.startPrank(user);
        WETH.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        // Rebalance Cellar to leverage into STETH.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, STETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 3;
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, STETH, type(uint256).max);
            data[3] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(aSTETH, type(uint256).max);
            data[4] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    function testIsBorrowingAnyFullRepay(uint256 assetsToBorrow) external checkBlockNumber {
        assetsToBorrow = bound(assetsToBorrow, 1, 1_000e18);

        // Add vanilla WETH to the cellar.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        // Add debt position to cellar.
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        uint256 assetsToLend = 2 * assetsToBorrow;

        deal(address(WETH), address(this), assetsToLend);
        cellar.deposit(assetsToLend, address(this));

        assertTrue(!aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should not be borrowing.");

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, assetsToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        deal(address(WETH), address(cellar), assetsToBorrow + 1);

        assertTrue(aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should be borrowing.");

        // Rebalance Cellar to repay debt in full.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepay(address(aWETH), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertTrue(!aTokenAdaptor.isBorrowingAny(address(cellar)), "Cellar should not be borrowing.");
    }

    function testHealthFactorChecks() external checkBlockNumber {
        uint256 assets = 100e18;

        // Add vanilla WETH to the cellar.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        // Add debt position to cellar.
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 targetHealthFactor = 1.052e18;
        uint256 ltv = 0.86e18;
        uint256 wethToBorrow = assets.mulDivDown(ltv, targetHealthFactor);
        uint256 wethToBorrowToTriggerHealthFactorRevert = 0.2e18;

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        // Borrow more WETH from Morpho to trigger HF check.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(aWETH, wethToBorrowToTriggerHealthFactorRevert);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor reverts because the health factor is too low.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoAaveV2DebtTokenAdaptor.MorphoAaveV2DebtTokenAdaptor__HealthFactorTooLow.selector
                )
            )
        );
        cellar.callOnAdaptor(data);

        // Try withdrawing WETH to lower Health Factor passed minimum.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(aWETH, 0.2e18);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor reverts because the health factor is too low.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.MorphoAaveV2ATokenAdaptor__HealthFactorTooLow.selector)
            )
        );
        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _setupCellarForBorrowing(Cellar target) internal {
        // Add required positions.
        target.addPosition(0, wethPosition, abi.encode(0), false);
        target.addPosition(1, stethPosition, abi.encode(0), false);
        target.addPosition(2, morphoAStEthPosition, abi.encode(0), false);
        target.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        // Change holding position to vanilla WETH.
        target.setHoldingPosition(wethPosition);
    }

    function getMorphoBalance(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pSupplyIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(poolToken).poolSupplyIndex, 1e27);
        return balanceInUnderlying;
    }

    function getMorphoDebt(address aToken, address user) public view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pBorrowIndex(aToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(aToken).poolBorrowIndex, 1e27);
        return balanceInUnderlying;
    }

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

    function _createBytesDataForSwap(ERC20 from, ERC20 to, uint256 fromAmount) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    function _createBytesDataToLend(address aToken, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.depositToAaveV2Morpho.selector, aToken, amountToLend);
    }

    function _createBytesDataToWithdraw(address aToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdrawFromAaveV2Morpho.selector,
                aToken,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrow(address debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.borrowFromAaveV2Morpho.selector,
                debtToken,
                amountToBorrow
            );
    }

    function _createBytesDataToRepay(address debtToken, uint256 amountToRepay) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.repayAaveV2MorphoDebt.selector,
                debtToken,
                amountToRepay
            );
    }
}
