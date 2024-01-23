// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { EulerDebtTokenAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";

contract TEnv {
    // General Variables.
    address public strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public gravityBridge = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    Registry public registry = Registry(0xd1c18363F81d8E6260511b38FcF1e8b710E7e31D);
    PriceRouter public priceRouter = PriceRouter(0xD8029A05bEB0FaF1215fBb064D98c39B28d317Ee);
    SwapRouter public swapRouter = SwapRouter(0xC356F0AC3a0d3fC18167d8ee62e0A8FB487D1719);
    ERC20Adaptor public erc20Adaptor = ERC20Adaptor(0x802818408DfC63E67ca4C56e2F5Ec37998Dd520C);
    FeesAndReservesAdaptor public feesAndReservesAdaptor =
        FeesAndReservesAdaptor(0xf260a0caD298BBB1b90c8D3EE24Ac896Ada65fA5);
    ZeroXAdaptor public zeroXAdaptor = ZeroXAdaptor(0x1bd161EF8EE43E72Ce8CfB156c2cA4f64E49c086);

    // Common ERC20s.
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);

    ERC20 public AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);

    ERC20 public aUSDCV3 = ERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);

    ERC20 public aWETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dWETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);

    ERC20 public aCBETH = ERC20(0x977b6fc5dE62598B08C85AC8Cf2b745874E8b78c);
    ERC20 public dCBETH = ERC20(0x0c91bcA95b5FE69164cE583A2ec9429A569798Ed);

    ERC20 public aRETH = ERC20(0xCc9EE9483f662091a1de4795249E24aC0aC2630f);
    ERC20 public dRETH = ERC20(0xae8593DD575FE29A9745056aA91C4b746eee62C8);

    // Chainlink PriceFeeds
    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    address public USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address public RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;

    address public AAVE_USD_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address public UNI_USD_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address public COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address public MKR_USD_FEED = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;

    // Registry Positions.
    // uint32 public eUsdcPosition = 1;
    // uint32 public eDaiPosition = 2;
    // uint32 public eUsdtPosition = 3;
    // uint32 public eUsdcLiquidPosition = 4;
    // uint32 public eDaiLiquidPosition = 5;
    // uint32 public eUsdtLiquidPosition = 6;
    // uint32 public debtUsdcPosition = 10;
    // uint32 public debtDaiPosition = 11;
    // uint32 public debtUsdtPosition = 12;
    // uint32 public eWethPositionV2 = 13;
    // uint32 public eWethLiquidPositionV2 = 14;
    // uint32 public debtWethPositionV2 = 15;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
}
