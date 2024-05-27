// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CErc20} from "src/interfaces/external/ICompound.sol";

contract ScrollAddresses {
    // Sommelier
    address public axelarProxyV0_0 = 0xEe75bA2C81C04DcA4b0ED6d1B7077c188FEde4d2;
    address public axelarGateway = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    string public axelarSommelierSender = "somm1lrneqhq4rq8nz2nk6vn3sanrxva7zuns8aa45g";
    address public strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address public devStrategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public deployerDeployerAddress = 0x61bfcdAFA35999FA93C10Ec746589EB93817a8b9;
    address public dev0Address = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public dev1Address = 0x6d3655EE04820f4385a910FD1898d4Ec6241F520;
    address public cosmos = address(0xCAAA);
    address public multisig = address(0);
    // address public deployerAddress = 0x70832E3e9a3268Fe9A5a47803e945fC34280B976;
    address public deployerAddress = 0xdAFAe2FfB48F1b5b710DD71FBaf8E6C7a67aBF89;

    // DeFi Ecosystem
    address public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public uniV3Router = 0xfc30937f5cDe93Df8d48aCAF7e6f5D8D8A31F636;
    address public uniV2Router = 0xfc30937f5cDe93Df8d48aCAF7e6f5D8D8A31F636;

    // ERC20s
    ERC20 public USDC = ERC20(0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4);
    ERC20 public WETH = ERC20(0x5300000000000000000000000000000000000004);
    ERC20 public WSTETH = ERC20(0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32);
    ERC20 public rETH = ERC20(0x53878B874283351D26d206FA512aEcE1Bef6C0dD);
    ERC20 public AXL_SOMM = ERC20(0x4e914bbDCDE0f455A8aC9d59d3bF739c46287Ed2);

    // Chainlink Datafeeds
    address public WETH_USD_FEED = 0x6bF14CB0A831078629D993FDeBcB182b21A8774C;
    address public USDC_USD_FEED = 0x43d12Fb3AfCAd5347fA764EeAB105478337b7200;
    address public WSTETH_ETH_FEED = 0xe428fbdbd61CC1be6C273dC0E27a1F43124a86F3;
    address public RETH_ETH_FEED = 0x3fBB86e564fC1303625BA88EaE55740f3A649d36;
    address public WSTETH_EXCHANGE_RATE_FEED = 0xE61Da4C909F7d86797a0D06Db63c34f76c9bCBDC;
    // address public RETH_EXCHANGE_RATE_FEED = 0xF3272CAfe65b190e76caAF483db13424a3e23dD2;
    address public SCROLL_SEQUENCER_UPTIME_FEED = 0x45c2b8C204568A03Dc7A2E32B71D67Fe97F908A9;

    // Aave V3 Tokens
    ERC20 public aV3USDC = ERC20(0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD);
    ERC20 public dV3USDC = ERC20(0x3d2E209af5BFa79297C88D6b57F89d792F6E28EE);
    ERC20 public aV3WETH = ERC20(0xf301805bE1Df81102C957f6d4Ce29d2B8c056B2a);
    ERC20 public dV3WETH = ERC20(0xfD7344CeB1Df9Cf238EcD667f4A6F99c6Ef44a56);
    ERC20 public aV3WSTETH = ERC20(0x5B1322eeb46240b02e20062b8F0F9908d525B09c);
    ERC20 public dV3WSTETH = ERC20(0x8a035644322129800C3f747f54Db0F4d3c0A2877);

    // Chainlink Automation Registry
    address public automationRegistry = address(0);
    address public automationRegistrar = address(0);

    // Uniswap V3
    address public uniswapV3PositionManager = 0xB39002E4033b162fAc607fc3471E205FA2aE5967;
    address public uniswapV3Factory = 0x70C62C8b8e801124A4Aa81ce07b637A3e83cb919;

    // Aave
    address public aaveV3Pool = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address public aaveV3Oracle = address(0);
}
