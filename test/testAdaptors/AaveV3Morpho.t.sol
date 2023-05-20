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
    ERC20 private WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IMorpho private morpho = IMorpho(0x33333aea097c193e66081E930c33020272b33333);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint32 private wethPosition;
    uint32 private wstethPosition;
    uint32 private morphoAWethPosition;
    uint32 private morphoAWstEthPosition;
    uint32 private morphoDebtWethPosition;

    modifier checkBlockNumber() {
        if (block.number < 16700000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16700000.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
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
                USDC,
                "AAVE Debt Cellar",
                "AAVE-CLR",
                aUSDCPosition,
                abi.encode(1.1e18),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(debtUSDCPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(0, debtUSDCPosition, abi.encode(0), true);

        USDC.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Currently tries to write a packed slot, so below call reverts.
        // stdstore.target(address(cellar)).sig(cellar.aavePool.selector).checked_write(address(pool));
    }

    function testDeposit() external checkBlockNumber {}

    function testWithdraw() external checkBlockNumber {}

    function testWithdrawalLogicNoDebt() external checkBlockNumber {}

    function testWithdrawalLogicWithDebt() external checkBlockNumber {}

    function testTotalAssets() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 1, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans() external checkBlockNumber {}

    function testTakingOutLoansInUntrackedPosition() external checkBlockNumber {}

    function testRepayingLoans() external checkBlockNumber {}

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

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToLendP2P(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdraw(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToWithdrawP2P(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }
}
