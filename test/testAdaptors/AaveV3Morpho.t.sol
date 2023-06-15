// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { MorphoAaveV3ATokenP2PAdaptor, IMorphoV3, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";
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

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveV3MorphoTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MorphoAaveV3ATokenP2PAdaptor private p2pATokenAdaptor;
    MorphoAaveV3ATokenCollateralAdaptor private collateralATokenAdaptor;
    MorphoAaveV3DebtTokenAdaptor private debtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IPoolV3 private pool = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    IMorphoV3 private morpho = IMorphoV3(0x33333aea097c193e66081E930c33020272b33333);
    WstEthExtension private wstEthOracle;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    address private aWstEthWhale = 0xAF06acFD1BD492B913d5807d562e4FC3A6343C4E;

    uint32 private wethPosition;
    uint32 private wstethPosition;
    uint32 private morphoAWethPosition;
    uint32 private morphoAWstEthPosition;
    uint32 private morphoDebtWethPosition;

    modifier checkBlockNumber() {
        if (block.number < 17297048) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17297048.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        wstEthOracle = new WstEthExtension();

        p2pATokenAdaptor = new MorphoAaveV3ATokenP2PAdaptor();
        collateralATokenAdaptor = new MorphoAaveV3ATokenCollateralAdaptor();
        debtTokenAdaptor = new MorphoAaveV3DebtTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor();

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

        // Timelock Multisig add WstEth to price router.
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(wstEthOracle));
        stor = PriceRouter.ChainlinkDerivativeStorage(90e18, 0.1e18, 0, true);
        price = uint256(wstEthOracle.latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        priceRouter.addAsset(WSTETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(p2pATokenAdaptor));
        registry.trustAdaptor(address(collateralATokenAdaptor));
        registry.trustAdaptor(address(debtTokenAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));

        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        wstethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WSTETH));
        morphoAWethPosition = registry.trustPosition(address(p2pATokenAdaptor), abi.encode(WETH));
        morphoAWstEthPosition = registry.trustPosition(address(collateralATokenAdaptor), abi.encode(WSTETH));
        morphoDebtWethPosition = registry.trustPosition(address(debtTokenAdaptor), abi.encode(WETH));

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                WETH,
                "MORPHO Debt Cellar",
                "MORPHO-CLR",
                morphoAWethPosition,
                abi.encode(4),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(p2pATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(collateralATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(debtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wstethPosition);
        cellar.addPositionToCatalogue(morphoAWethPosition);
        cellar.addPositionToCatalogue(morphoAWstEthPosition);
        cellar.addPositionToCatalogue(morphoDebtWethPosition);

        // cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        // cellar.addPosition(0, wethPosition, abi.encode(0), false);

        WETH.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Force whale out of their WSTETH position.
        vm.prank(aWstEthWhale);
        pool.withdraw(address(WSTETH), 1_000e18, aWstEthWhale);
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

        // Pass a little bit of time so that we can withdraw the full amount.
        // Morpho deposit rounds down.
        vm.warp(block.timestamp + 300);

        cellar.withdraw(assets, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external checkBlockNumber {
        assets = bound(assets, 0.01e18, 10_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 2, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        uint256 wethDebt = morpho.borrowBalance(address(WETH), address(cellar));

        assertApproxEqAbs(wethDebt, assets / 4, 1, "WETH debt should equal assets / 4.");
        assertApproxEqRel(cellar.totalAssets(), assets, 0.997e18, "Total assets should equal assets.");
    }

    function testRepayingLoans(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        uint256 wethDebt = morpho.borrowBalance(address(WETH), address(cellar));

        assertApproxEqAbs(wethDebt, assets / 4, 1, "WETH debt should equal assets / 4.");
        assertApproxEqRel(cellar.totalAssets(), assets, 0.997e18, "Total assets should equal assets.");

        // Now repay half the debt.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToRepay = wethDebt / 2;
            adaptorCalls[0] = _createBytesDataToRepay(WETH, wethToRepay);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        wethDebt = morpho.borrowBalance(address(WETH), address(cellar));

        assertApproxEqAbs(wethDebt, assets / 8, 1, "WETH debt should equal assets / 8.");
        assertApproxEqRel(cellar.totalAssets(), assets, 0.997e18, "Total assets should equal assets.");
    }

    function testWithdrawalLogic(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 0.01e18, 400e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }
        // Supply WETH as collateral p2p on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendP2P(WETH, type(uint256).max, 4);
            data[3] = Cellar.AdaptorCall({ adaptor: address(p2pATokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        // The only assets withdrawable from the cellar should be the WETH lent P2P.
        uint256 wethP2PLend = morpho.supplyBalance(address(WETH), address(cellar));

        uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();
        assertEq(wethP2PLend, assetsWithdrawable, "Only assets withdrawable should be in P2P Lending.");

        // User withdraws as much as possible.
        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
        assertEq(WETH.balanceOf(address(this)), wethP2PLend, "Withdraw should have sent P2P assets to user.");
        assertEq(morpho.supplyBalance(address(WETH), address(cellar)), 0, "There should be no more WETH supplied.");

        assertEq(cellar.totalAssetsWithdrawable(), 0, "There should be no more assets withdrawable.");

        // Cellar must repay ALL of its WETH debt before WSTETH collateral can be withdrawn.
        uint256 wethDebt = morpho.borrowBalance(address(WETH), address(cellar));

        // Give the cellar enough WETH to pay off the debt.
        deal(address(WETH), address(cellar), wethDebt);

        data = new Cellar.AdaptorCall[](1);
        // Repay the debt.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepay(WETH, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        // Note 0.1% deviation happens because of swap fees and slippage.
        assertApproxEqRel(
            cellar.totalAssetsWithdrawable(),
            assets,
            0.01e18,
            "Withdrawable assets should equal assets in."
        );

        assertEq(morpho.borrowBalance(address(WETH), address(cellar)), 0, "Borrow balance should be zero.");
        assertEq(morpho.userBorrows(address(cellar)).length, 0, "User borrows array should be empty.");

        maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
        uint256 expectedOut = priceRouter.getValue(WETH, maxAssets, WSTETH);
        assertApproxEqAbs(
            WSTETH.balanceOf(address(this)),
            expectedOut,
            1,
            "Withdraw should have sent collateral assets to user."
        );
    }

    function testTakingOutLoansInUntrackedPosition(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);
        cellar.removePosition(0, true);

        assets = bound(assets, 0.01e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 4;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor reverts because WETH debt is not tracked.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoAaveV3DebtTokenAdaptor.MorphoAaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(WETH)
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
            adaptorCalls[0] = _createBytesDataToRepay(WETH, wethToRepay);
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
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Swap WETH for WSTETH.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Supply WETH as collateral p2p on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendP2P(WETH, type(uint256).max, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(p2pATokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Strategist tries calling withdraw on collateral.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.withdraw.selector,
                1,
                strategist,
                abi.encode(WSTETH),
                abi.encode(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__ExternalReceiverBlocked.selector)));
        cellar.callOnAdaptor(data);

        // Strategist tries calling withdraw on p2p.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.withdraw.selector,
                1,
                strategist,
                abi.encode(WETH),
                abi.encode(0)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(p2pATokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__ExternalReceiverBlocked.selector)));
        cellar.callOnAdaptor(data);
    }

    function testHealthFactor(uint256 assets) external checkBlockNumber {
        _setupCellarForBorrowing(cellar);

        assets = bound(assets, 10e18, 1_000e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a swap by minting cellar the correct amount of WSTETH.
        deal(address(WETH), address(cellar), 0);
        uint256 wstEthToMint = priceRouter.getValue(WETH, assets, WSTETH);
        deal(address(WSTETH), address(cellar), wstEthToMint);

        uint256 targetHealthFactor = 1.06e18;
        uint256 ltv = 0.93e18;
        uint256 wethToBorrow = assets.mulDivDown(ltv, targetHealthFactor);

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, wstEthToMint);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[1] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IMorphoV3.LiquidityData memory liquidityData = morpho.liquidityData(address(cellar));
        uint256 morphoHealthFactor = uint256(1e18).mulDivDown(liquidityData.maxDebt, liquidityData.debt);

        assertApproxEqRel(
            morphoHealthFactor,
            targetHealthFactor,
            0.0025e18,
            "Morpho health factor should equal target."
        );

        // Make sure that morpho Health factor is the same as ours.
        assertApproxEqAbs(
            _getUserHealthFactor(address(cellar)),
            morphoHealthFactor,
            1,
            "Our health factor should equal morphos."
        );
    }

    function testHealthFactorChecks() external {
        // Need to borrow, and lower the health factor below 1.05, then need to withdraw to lower health factor below 1.05.
        _setupCellarForBorrowing(cellar);

        uint256 assets = 100e18;
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a swap by minting cellar the correct amount of WSTETH.
        deal(address(WETH), address(cellar), 0);
        uint256 wstEthToMint = priceRouter.getValue(WETH, assets, WSTETH);
        deal(address(WSTETH), address(cellar), wstEthToMint);

        uint256 targetHealthFactor = 1.052e18;
        uint256 ltv = 0.93e18;
        uint256 wethToBorrow = assets.mulDivDown(ltv, targetHealthFactor);
        uint256 wethToBorrowToTriggerHealthFactorRevert = assets.mulDivDown(ltv, 1.04e18) - wethToBorrow;

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, wstEthToMint);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[1] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        // Strategist tries to borrow more.
        data = new Cellar.AdaptorCall[](1);
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrowToTriggerHealthFactorRevert, 4);
            data[0] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor reverts because the health factor is too low.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoAaveV3DebtTokenAdaptor.MorphoAaveV3DebtTokenAdaptor__HealthFactorTooLow.selector
                )
            )
        );
        cellar.callOnAdaptor(data);

        // If strategist tries to withdraw some collateral, the withdraw also reverts.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 amountToWithdraw = 1e18;
            adaptorCalls[0] = _createBytesDataToWithdraw(WSTETH, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }

        // callOnAdaptor should revert because withdraw lowers Health Factor too far.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoAaveV3ATokenCollateralAdaptor.MorphoAaveV3ATokenCollateralAdaptor__HealthFactorTooLow.selector
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegrationRealYieldEth(uint256 assets) external checkBlockNumber {
        // Setup cellar so that aSTETH is illiquid.
        // Then have strategist loop into STETH.
        // -Deposit STETH as collateral, and borrow WETH, repeat.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        cellar.addPosition(0, wstethPosition, abi.encode(0), false);
        cellar.addPosition(0, morphoAWstEthPosition, abi.encode(false), false);
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        // Change holding position to vanilla WETH.
        cellar.setHoldingPosition(wethPosition);

        // Remove unused aWETH Morpho position from the cellar.
        cellar.removePosition(3, false);

        // assets = bound(assets, 1e18, 400e18);
        assets = 400e18;
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
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            uint256 wethToBorrow = assets / 3;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, type(uint256).max);
            data[3] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        // Supply WSTETH as collateral on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WSTETH, type(uint256).max);
            data[4] = Cellar.AdaptorCall({ adaptor: address(collateralATokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPER FUNCTIONS =========================================
    uint256 internal constant WAD = 1e18;

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        // to avoid overflow, a <= (type(uint256).max - halfB) / WAD
        assembly {
            if or(iszero(b), iszero(iszero(gt(a, div(sub(not(0), div(b, 2)), WAD))))) {
                revert(0, 0)
            }

            c := div(add(mul(a, WAD), div(b, 2)), b)
        }
    }

    function _getUserHealthFactor(address user) internal view returns (uint256) {
        IMorphoV3.LiquidityData memory liquidityData = morpho.liquidityData(user);

        return liquidityData.debt > 0 ? wadDiv(liquidityData.maxDebt, liquidityData.debt) : type(uint256).max;
    }

    function _setupCellarForBorrowing(Cellar target) internal {
        // Add required positions.
        target.addPosition(0, wethPosition, abi.encode(0), false);
        target.addPosition(1, wstethPosition, abi.encode(0), false);
        target.addPosition(2, morphoAWstEthPosition, abi.encode(0), false);
        target.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        // Change holding position to vanilla WETH.
        target.setHoldingPosition(wethPosition);
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

    function _createBytesDataToLendP2P(
        ERC20 tokenToLend,
        uint256 amountToLend,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend,
                maxIterations
            );
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend
            );
    }

    function _createBytesDataToWithdrawP2P(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.withdrawFromAaveV3Morpho.selector,
                tokenToWithdraw,
                amountToWithdraw,
                maxIterations
            );
    }

    function _createBytesDataToWithdraw(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.withdrawFromAaveV3Morpho.selector,
                tokenToWithdraw,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrow(
        ERC20 debtToken,
        uint256 amountToBorrow,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.borrowFromAaveV3Morpho.selector,
                debtToken,
                amountToBorrow,
                maxIterations
            );
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.repayAaveV3MorphoDebt.selector,
                tokenToRepay,
                amountToRepay
            );
    }
}
