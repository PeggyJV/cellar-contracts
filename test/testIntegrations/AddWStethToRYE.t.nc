// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/WstEthExtension.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";

import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract AddWstEthToRYETest is Test {
    using Math for uint256;

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    Cellar private rye = Cellar(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 public WstEth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // Aave V3 Positions
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3WstEth = ERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);
    ERC20 public dV3WstEth = ERC20(0xC96113eED8cAB59cD8A66813bCB0cEb29F06D2e4);

    address public uniswapV3Adaptor = 0x0bD9a2c1917E3a932A4a712AEE38FF63D35733Fb;
    address public aaveV3DebtTokenAdaptor = 0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7;
    address public aaveV3AtokenAdaptor = 0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6;
    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    WstEthExtension private wstEthOracle;

    function setUp() external {
        wstEthOracle = new WstEthExtension();
    }

    function testAddingWstEthSupport() external {
        if (block.number < 16999774) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16999774.");
            return;
        }

        // Timelock Multisig add WstEth to price router.
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            address(wstEthOracle)
        );
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            90e18,
            0.1e18,
            0,
            true
        );
        uint256 price = uint256(wstEthOracle.latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC);
        price = price.changeDecimals(6, 8);
        vm.prank(controller);
        priceRouter.addAsset(WstEth, settings, abi.encode(stor), price);

        // Multisig adds new positions to price router.
        vm.startPrank(multisig);
        uint32 wStEth = registry.trustPosition(erc20Adaptor, abi.encode(address(WstEth)));
        uint32 aWstEth = registry.trustPosition(aaveV3AtokenAdaptor, abi.encode(address(aV3WstEth)));
        uint32 wStEthWeth = registry.trustPosition(uniswapV3Adaptor, abi.encode(WstEth, WETH));
        vm.stopPrank();

        // Strategist or Governance calls `addPositionToCatalogue`.
        vm.startPrank(gravityBridge);
        rye.addPositionToCatalogue(wStEth);
        rye.addPositionToCatalogue(aWstEth);
        rye.addPositionToCatalogue(wStEthWeth);

        // Strategist calls `addPosition`
        rye.addPosition(8, aWstEth, abi.encode(0), false);
        rye.addPosition(0, wStEth, abi.encode(0), false);
        rye.addPosition(8, wStEthWeth, abi.encode(0), false);
        vm.stopPrank();

        // At this point the Cellar can now use wstEth positions.

        // Whale enters the cellar.
        uint256 assets = 1_000e18;
        deal(address(WETH), address(this), assets);
        WETH.approve(address(rye), assets);
        rye.deposit(assets, address(this));

        // Strategist enters aWSTETH position, and an LP position.
        // Simulate a swap for 3/4 of the ETH for WSTETH.
        uint256 wstethAmount = priceRouter.getValue(WETH, assets.mulDivDown(3, 4), WstEth);
        deal(address(WETH), address(rye), assets.mulDivDown(1, 4));
        deal(address(WstEth), address(rye), wstethAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToOpenLP(WstEth, WETH, 500, type(uint256).max, type(uint256).max, 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WstEth, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveV3AtokenAdaptor), callData: adaptorCalls });
        }

        uint256 ryeLPBalance = positionManager.balanceOf(address(rye));

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        assertGt(aV3WstEth.balanceOf(address(rye)), 0, "RYE should have WSTETH in Aave V3");
        assertEq(positionManager.balanceOf(address(rye)), ryeLPBalance + 1, "RYE should have minted 1 more LP token.");
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

    function _createBytesDataToCloseLP(uint256 id) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, id, 0, 0);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }
}
