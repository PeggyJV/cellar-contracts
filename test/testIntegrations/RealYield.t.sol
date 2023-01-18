// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
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
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RealYieldTest is Test {
    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

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

    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x7C4262f83e6775D6ff6fE8d9ab268611Ed9d13Ee);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0x8646F6A7658a7B6399dc238d6018d0344ad81D3d);
    CTokenAdaptor private cTokenAdaptor = CTokenAdaptor(0x26DbA82495f6189DDe7648Ae88bEAd46C402F078);
    VestingSimpleAdaptor private vestingAdaptor = VestingSimpleAdaptor(0x1eAA1a100a460f46A2032f0402Bc01FE89FaAB60);
    VestingSimple private usdcVestor = VestingSimple(0xd944D0e62de2ae742C4CA085e80222f58B69b231);

    Cellar private realYield;
    Registry private registry;

    function setUp() external {
        realYield = Cellar(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);

        registry = Registry(0x2Cbd27E034FEE53f79b607430dA7771B22050741);
    }

    function testRealYield() external {
        if (block.number < 16429203) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16429203.");
            return;
        }

        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(realYield), assets);
        realYield.deposit(assets, address(this));

        assertApproxEqAbs(aUSDC.balanceOf(address(realYield)), assets, 1, "Assets should have been deposited to Aave.");

        // Have strategist withdraw from Aave, deposit some into Compound, then add liquidity to Uniswap.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](2);
        adaptorCallsFirstAdaptor[0] = _createBytesDataToWithdraw(USDC, assets / 2);
        adaptorCallsFirstAdaptor[1] = _createBytesDataForSwap(USDC, USDT, 500, assets / 8);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsFirstAdaptor });

        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToOpenLP(USDC, USDT, 500, assets / 8, type(uint256).max, 100);

        data[1] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCallsSecondAdaptor });

        bytes[] memory adaptorCallsThirdAdaptor = new bytes[](1);
        adaptorCallsThirdAdaptor[0] = _createBytesDataToLend(cUSDC, type(uint256).max);

        data[2] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCallsThirdAdaptor });

        vm.prank(strategist);
        realYield.callOnAdaptor(data);

        // Give the cellar a large amount of yield by minting it COMP, then have it swap COMP for WETH, then USDC and vest it.
        deal(address(COMP), address(realYield), 100e18);
        data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataForSwap(COMP, WETH, 3000, 100e18);
        adaptorCalls[1] = _createBytesDataForOracleSwap(WETH, USDC, 500, type(uint256).max);
        adaptorCalls[2] = _createBytesDataToDeposit(usdcVestor, type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        vm.prank(strategist);
        realYield.callOnAdaptor(data);

        uint256 vestedBalance = usdcVestor.vestedBalanceOf(address(realYield));
        console.log("Vested Assets", vestedBalance);

        vm.warp(block.timestamp + 7 days);

        vestedBalance = usdcVestor.vestedBalanceOf(address(realYield));
        console.log("Vested Assets", vestedBalance);
    }

    function _createBytesDataToDeposit(VestingSimple _vesting, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(VestingSimpleAdaptor.depositToVesting.selector, address(_vesting), amount);
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

    function _createBytesDataToWithdraw(ERC20 tokenToWithdraw, uint256 amountToWithdraw)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToLend(CErc20 market, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
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
        return
            abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
    }

    function _getUpperAndLowerTick(
        ERC20 token0,
        ERC20 token1,
        uint24 fee,
        int24 size,
        int24 shift
    ) internal view returns (int24 lower, int24 upper) {
        uint256 price = priceRouter.getExchangeRate(token1, token0);
        uint256 ratioX192 = ((10**token1.decimals()) << 192) / (price);
        uint160 sqrtPriceX96 = SafeCast.toUint160(_sqrt(ratioX192));
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        tick = tick + shift;

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(address(token0), address(token1), fee));
        int24 spacing = pool.tickSpacing();
        lower = tick - (tick % spacing);
        lower = lower - ((spacing * size) / 2);
        upper = lower + spacing * size;
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

    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }
}
