// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { TEnv } from "script/test/TEnv.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Compound helpers.
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";

// Import Aave helpers.
import { IPool } from "src/interfaces/external/IPool.sol";

// Import UniV3 helpers.
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

// Import test helpers
import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RealYieldEthTest is Test, TEnv {
  using SafeTransferLib for ERC20;
  using Math for uint256;
  using stdStorage for StdStorage;

  CellarFactory private factory;
  Cellar private cellar = Cellar(0xD3bDdF3143ce850f734dE7B308FE7BD841367fCD);

  PriceRouter private priceRouter;
  SwapRouter private swapRouter;
  VestingSimple private usdcVestor;

  Registry private registry;

  uint8 private constant CHAINLINK_DERIVATIVE = 1;

  address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  INonfungiblePositionManager internal positionManager =
    INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

  IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

  Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

  ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
  ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
  ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
  ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
  ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
  ERC20 private aDAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
  ERC20 private dDAI = ERC20(0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d);
  ERC20 private aUSDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);
  ERC20 private dUSDT = ERC20(0x531842cEbbdD378f8ee36D171d6cC9C4fcf475Ec);
  CErc20 private cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
  CErc20 private cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
  CErc20 private cUSDT = CErc20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);

  address private immutable strategist = vm.addr(0xBEEF);

  address private immutable cosmos = vm.addr(0xCAAA);

  // Define Adaptors.
  ERC20Adaptor private erc20Adaptor;
  UniswapV3Adaptor private uniswapV3Adaptor;
  AaveATokenAdaptor private aaveATokenAdaptor;
  AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
  CTokenAdaptor private cTokenAdaptor;
  VestingSimpleAdaptor private vestingAdaptor;

  // Chainlink PriceFeeds
  address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
  address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  address private COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
  address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

  // Base positions.
  uint32 private usdcPosition;
  uint32 private daiPosition;
  uint32 private usdtPosition;

  // Uniswap V3 positions.
  uint32 private usdcDaiPosition;
  uint32 private usdcUsdtPosition;

  // Aave positions.
  uint32 private aUSDCPosition;
  uint32 private dUSDCPosition;
  uint32 private aDAIPosition;
  uint32 private dDAIPosition;
  uint32 private aUSDTPosition;
  uint32 private dUSDTPosition;

  // Compound positions.
  uint32 private cUSDCPosition;
  uint32 private cDAIPosition;
  uint32 private cUSDTPosition;

  // Vesting positions.
  uint32 private vUSDCPosition;

  function setUp() external {}

  function testDeposit() external {
    deal(address(WETH), address(this), 1e18);
    WETH.approve(address(cellar), 1e18);
    cellar.deposit(1e18, address(this));
  }

  // ========================================= HELPER FUNCTIONS =========================================
  function _sqrt(uint256 _x) internal pure returns (uint256 y) {
    uint256 z = (_x + 1) / 2;
    y = _x;
    while (z < y) {
      y = z;
      z = (_x / z + z) / 2;
    }
  }

  /**
   * @notice Get the upper and lower tick around token0, token1.
   * @param token0 The 0th Token in the UniV3 Pair
   * @param token1 The 1st Token in the UniV3 Pair
   * @param fee The desired fee pool
   * @param size Dictates the amount of ticks liquidity will cover
   *             @dev Must be an even number
   * @param shift Allows the upper and lower tick to be moved up or down relative
   *              to current price. Useful for range orders.
   */
  function _getUpperAndLowerTick(
    ERC20 token0,
    ERC20 token1,
    uint24 fee,
    int24 size,
    int24 shift
  ) internal view returns (int24 lower, int24 upper) {
    uint256 price = priceRouter.getExchangeRate(token1, token0);
    uint256 ratioX192 = ((10 ** token1.decimals()) << 192) / (price);
    uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
    int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    tick = tick + shift;

    IUniswapV3Pool pool = IUniswapV3Pool(v3factory.getPool(address(token0), address(token1), fee));
    int24 spacing = pool.tickSpacing();
    lower = tick - (tick % spacing);
    lower = lower - ((spacing * size) / 2);
    upper = lower + spacing * size;
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
    bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
    return abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
  }

  function _createBytesDataToOpenLP(
    ERC20 token0,
    ERC20 token1,
    uint24 poolFee,
    uint256 amount0,
    uint256 amount1,
    int24 size
  ) internal view returns (bytes memory) {
    (int24 lower, int24 upper) = _getUpperAndLowerTick(token0, token1, poolFee, size, 0);
    return
      abi.encodeWithSelector(
        UniswapV3Adaptor.openPosition.selector,
        token0,
        token1,
        poolFee,
        amount0,
        amount1,
        0,
        0,
        lower,
        upper
      );
  }

  function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
    uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
    return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
  }

  function _createBytesDataToAddLP(
    address owner,
    uint256 index,
    uint256 amount0,
    uint256 amount1
  ) internal view returns (bytes memory) {
    uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
    return abi.encodeWithSelector(UniswapV3Adaptor.addToPosition.selector, tokenId, amount0, amount1, 0, 0);
  }

  function _createBytesDataToTakeLP(
    address owner,
    uint256 index,
    uint256 liquidityPer
  ) internal view returns (bytes memory) {
    uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
    (, , , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(tokenId);
    uint128 liquidity;
    if (liquidity >= 1e18) liquidity = type(uint128).max;
    else liquidity = uint128((positionLiquidity * liquidityPer) / 1e18);
    return abi.encodeWithSelector(UniswapV3Adaptor.takeFromPosition.selector, tokenId, liquidity, 0, 0);
  }

  function _createBytesDataToCollectFees(
    address owner,
    uint256 index,
    uint128 amount0,
    uint128 amount1
  ) internal view returns (bytes memory) {
    uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
    return abi.encodeWithSelector(UniswapV3Adaptor.collectFees.selector, tokenId, amount0, amount1);
  }

  function _createBytesDataToOpenRangeOrder(
    ERC20 token0,
    ERC20 token1,
    uint24 poolFee,
    uint256 amount0,
    uint256 amount1
  ) internal view returns (bytes memory) {
    int24 lower;
    int24 upper;
    if (amount0 > 0) {
      (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, 100);
    } else {
      (lower, upper) = _getUpperAndLowerTick(token0, token1, poolFee, 2, -100);
    }

    return
      abi.encodeWithSelector(
        UniswapV3Adaptor.openPosition.selector,
        token0,
        token1,
        poolFee,
        amount0,
        amount1,
        0,
        0,
        lower,
        upper
      );
  }

  function _createBytesDataToLendOnAave(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
  }

  function _createBytesDataToWithdrawFromAave(
    ERC20 tokenToWithdraw,
    uint256 amountToWithdraw
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
  }

  function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
  }

  function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
  }

  function _createBytesDataToSwapAndRepay(
    ERC20 from,
    ERC20 to,
    uint24 fee,
    uint256 amount
  ) internal pure returns (bytes memory) {
    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(to);
    uint24[] memory poolFees = new uint24[](1);
    poolFees[0] = fee;
    bytes memory params = abi.encode(path, poolFees, amount, 0);
    return
      abi.encodeWithSelector(
        AaveDebtTokenAdaptor.swapAndRepay.selector,
        from,
        to,
        amount,
        SwapRouter.Exchange.UNIV3,
        params
      );
  }

  function _createBytesDataToFlashLoan(
    address[] memory loanToken,
    uint256[] memory loanAmount,
    bytes memory params
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
  }

  function _createBytesDataForOracleSwap(
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
    bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
    return
      abi.encodeWithSelector(
        BaseAdaptor.oracleSwap.selector,
        from,
        to,
        type(uint256).max,
        SwapRouter.Exchange.UNIV3,
        params,
        0.99e18
      );
  }

  function _createBytesDataToLendOnCompound(CErc20 market, uint256 amountToLend) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
  }

  function _createBytesDataToWithdrawFromCompound(
    CErc20 market,
    uint256 amountToWithdraw
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
  }

  function _createBytesDataToClaimComp() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
  }

  function _createBytesDataForClaimCompAndSwap(
    ERC20 from,
    ERC20 to,
    uint24 poolFee
  ) internal pure returns (bytes memory) {
    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(to);
    uint24[] memory poolFees = new uint24[](1);
    poolFees[0] = poolFee;
    bytes memory params = abi.encode(path, poolFees, 0, 0);
    return
      abi.encodeWithSelector(CTokenAdaptor.claimCompAndSwap.selector, to, SwapRouter.Exchange.UNIV3, params, 0.99e18);
  }
}
