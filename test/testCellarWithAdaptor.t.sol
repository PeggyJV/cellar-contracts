// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/lending/aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/lending/aave/AaveDebtTokenAdaptor.sol";
import { SushiAdaptor } from "src/modules/adaptors/farming/SushiAdaptor.sol";
import { IPool } from "src/interfaces/IPool.sol";
import { IMasterChef } from "src/interfaces/IMasterChef.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarWithAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    SushiAdaptor private sushiAdaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dWETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 private CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private dCVX = ERC20(0x4Ae5E4409C6Dbc84A00f9f89e4ba096603fb7d50);
    ERC20 private SUSHI = ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef

    function setUp() external {
        aaveATokenAdaptor = new AaveATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor();
        //sushiAdaptor = new SushiAdaptor();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        // Setup Cellar:
        address[] memory positions = new address[](5);
        positions[0] = address(aUSDC);
        positions[1] = address(dWETH);
        positions[2] = address(WETH);
        positions[3] = address(dCVX);
        positions[4] = address(CVX);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](5);
        positionTypes[0] = Cellar.PositionType.Adaptor;
        positionTypes[1] = Cellar.PositionType.Adaptor;
        positionTypes[2] = Cellar.PositionType.ERC20;
        positionTypes[3] = Cellar.PositionType.Adaptor;
        positionTypes[4] = Cellar.PositionType.ERC20;

        cellar = new Cellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(aUSDC),
            Cellar.WithdrawType.ORDERLY,
            "AAVE Debt Cellar",
            "AAVE-CLR"
        );

        cellar.setIdToAdaptor(1, address(aaveATokenAdaptor));
        cellar.setIdToAdaptor(2, address(aaveDebtTokenAdaptor));
        cellar.trustPosition(address(aUSDC), Cellar.PositionType.Adaptor, false, 1, abi.encode(address(aUSDC)));
        cellar.trustPosition(address(dWETH), Cellar.PositionType.Adaptor, true, 2, abi.encode(address(dWETH)));
        cellar.trustPosition(address(WETH), Cellar.PositionType.ERC20, false, 0, abi.encode(address(WETH)));
        cellar.trustPosition(address(dCVX), Cellar.PositionType.Adaptor, true, 2, abi.encode(address(dCVX)));
        cellar.trustPosition(address(CVX), Cellar.PositionType.ERC20, false, 0, abi.encode(address(CVX)));

        cellar.pushPosition(positions[0]);
        cellar.pushPosition(positions[1]);
        cellar.pushPosition(positions[2]);
        cellar.pushPosition(positions[3]);
        cellar.pushPosition(positions[4]);

        //TODO price router stuff
        priceRouter.addAsset(USDC, ERC20(address(0)), 0, 100e8, 1 days);
        priceRouter.addAsset(CVX, ERC20(address(0)), 0, 10000e8, 1 days);
        priceRouter.addAsset(WETH, ERC20(Denominations.ETH), 0, 100000e8, 1 days);

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(this), type(uint224).max);
        USDC.approve(address(cellar), type(uint224).max);
    }

    function testAavePositions() external {
        cellar.deposit(10000e6, address(this));
        Cellar.AdaptorCall[] memory callInfo = new Cellar.AdaptorCall[](1);
        bytes4[] memory functionSigs = new bytes4[](3);
        bytes[] memory callData = new bytes[](3);
        bool[] memory isRevertOkay = new bool[](3);
        //borrow data
        functionSigs[0] = AaveDebtTokenAdaptor.borrowFromAave.selector;
        callData[0] = abi.encode(address(WETH), 1e18);
        isRevertOkay[0] = false;
        functionSigs[1] = AaveDebtTokenAdaptor.borrowFromAave.selector;
        callData[1] = abi.encode(address(CVX), 200e18);
        isRevertOkay[1] = false;

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(CVX);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 10000;
        bytes memory swapData = abi.encode(path, poolFees, 1e18, 0);
        functionSigs[2] = BaseAdaptor.swap.selector;
        callData[2] = abi.encode(WETH, 1e18, SwapRouter.Exchange.UNIV3, swapData);

        callInfo[0] = Cellar.AdaptorCall({
            adaptorId: 2,
            functionSigs: functionSigs,
            callData: callData,
            isRevertOkay: isRevertOkay
        });

        //SP Calls on Adaptor
        cellar.callOnAdaptor(callInfo);

        console.log("Cellar aUSDC balance: ", aUSDC.balanceOf(address(cellar)));
        console.log("Cellar dWETH balance: ", dWETH.balanceOf(address(cellar)));
        console.log("Cellar  WETH balance: ", WETH.balanceOf(address(cellar)));
        console.log("Cellar  dCVX balance: ", dCVX.balanceOf(address(cellar)));
        console.log("Cellar   CVX balance: ", CVX.balanceOf(address(cellar)));
        console.log("Cellar  Total Assets: ", cellar.totalAssets());
    }
}
