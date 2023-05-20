// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { MorphoAaveV3ATokenP2PAdaptor, IMorpho, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
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

    IMorpho private morpho = IMorpho(0x33333aea097c193e66081E930c33020272b33333);
    WstEthExtension private wstEthOracle;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // TODO force this whale out of their aWstEth position, for the equivalent of 1k WETH.
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
        priceRouter = new PriceRouter();

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

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
        // Add required positions.
        cellar.addPosition(0, wethPosition, abi.encode(0), false);
        cellar.addPosition(1, wstethPosition, abi.encode(0), false);
        cellar.addPosition(2, morphoAWstEthPosition, abi.encode(0), false);
        cellar.addPosition(0, morphoDebtWethPosition, abi.encode(0), true);

        // Change holding position to vanilla WETH.
        cellar.setHoldingPosition(wethPosition);

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
            uint256 wethToBorrow = assets / 2;
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(debtTokenAdaptor), callData: adaptorCalls });
        }

        // Perfrom callOnAdaptor.
        cellar.callOnAdaptor(data);

        uint256 wethDebt = morpho.borrowBalance(address(WETH), address(cellar));

        assertApproxEqAbs(wethDebt, assets / 2, 1, "WETH debt should equal assets / 2.");
        assertApproxEqRel(cellar.totalAssets(), assets, 0.997e18, "Total assets should equal assets.");
    }

    function testRepayingLoans() external checkBlockNumber {}

    function testWithdrawalLogicNoDebt() external checkBlockNumber {}

    function testWithdrawalLogicWithDebt() external checkBlockNumber {}

    function testTakingOutLoansInUntrackedPosition() external checkBlockNumber {}

    function testRepayingDebtThatIsNotOwed() external checkBlockNumber {}

    function testBlockExternalReceiver() external checkBlockNumber {}

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegration() external {}

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
