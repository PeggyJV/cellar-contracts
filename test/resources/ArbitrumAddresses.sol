// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract ArbitrumAddresses {
    // Sommelier
    address public gravityBridgeAddress = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address public strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address public testStrategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public cosmos = address(0xCAAA);
    address public multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address public deployerAddress = 0x70832E3e9a3268Fe9A5a47803e945fC34280B976;
    address public dev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    // ERC20s
    ERC20 public USDC = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    ERC20 public USDCe = ERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    ERC20 public WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public WBTC = ERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ERC20 public USDT = ERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    ERC20 public DAI = ERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    ERC20 public FRAX = ERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    ERC20 public WSTETH = ERC20(0x0fBcbaEA96Ce0cF7Ee00A8c19c3ab6f5Dc8E1921);
    ERC20 public BAL = ERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    ERC20 public COMP = ERC20(0x354A6dA3fcde098F8389cad84b0182725c6C91dE);
    ERC20 public LINK = ERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
    ERC20 public cbETH = ERC20(0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f);

    // Chainlink Datafeeds
    address public WETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address public USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public WBTC_USD_FEED = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address public WSTETH_ETH_FEED = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
    address public DAI_USD_FEED = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
    address public USDT_USD_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    address public COMP_USD_FEED = 0xe7C53FFd03Eb6ceF7d208bC4C13446c76d1E5884;
    address public CBETH_ETH_FEED = 0xa668682974E3f121185a3cD94f00322beC674275;
    address public BAL_USD_FEED = 0xBE5eA816870D11239c543F84b71439511D70B94f;
    address public LINK_USD_FEED = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
    address public RPL_USD_FEED = 0xF0b7159BbFc341Cc41E7Cb182216F62c6d40533D;
    address public FRAX_USD_FEED = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;

    // Aave V3
    address public aaveV3Pool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public aaveV3Oracle = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

    // Aave V3 Tokens
    ERC20 public aV3WETH = ERC20(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);
    ERC20 public dV3WETH = ERC20(0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351);
    ERC20 public aV3USDC = ERC20(0x724dc807b04555b71ed48a6896b6F41593b8C637);
    ERC20 public dV3USDC = ERC20(0xf611aEb5013fD2c0511c9CD55c7dc5C1140741A6);
    ERC20 public aV3USDCe = ERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD);
    ERC20 public dV3USDCe = ERC20(0xFCCf3cAbbe80101232d343252614b6A3eE81C989);
    ERC20 public aV3DAI = ERC20(0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE);
    ERC20 public dV3DAI = ERC20(0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC);
    ERC20 public aV3WBTC = ERC20(0x078f358208685046a11C85e8ad32895DED33A249);
    ERC20 public dV3WBTC = ERC20(0x92b42c66840C7AD907b4BF74879FF3eF7c529473);
    ERC20 public aV3USDT = ERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);
    ERC20 public dV3USDT = ERC20(0xfb00AC187a8Eb5AFAE4eACE434F493Eb62672df7);

    // Chainlink Automation Registry
    address public automationRegistry = 0x37D9dC70bfcd8BC77Ec2858836B923c560E891D1;

    // Uniswap V3
    address public uniPositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // Sushiswap V3
    address public sushiPositionManager = 0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49;

    // 1inch
    address public oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    // 0x
    address public zeroXRouter = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // Balancer
    address public vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
}
