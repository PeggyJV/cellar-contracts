// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CErc20} from "src/interfaces/external/ICompound.sol";

contract BaseAddresses {
    // Sommelier
    // address public axelarProxyV0_0 = address(0);
    // address public axelarGateway = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    // string public axelarSommelierSender = "somm1lrneqhq4rq8nz2nk6vn3sanrxva7zuns8aa45g";
    // address public strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address public devStrategist = 0x2454c7bd6E1Ee62162c97a7E0E2A82D6E1E940AA;
    // address public deployerDeployerAddress = 0x61bfcdAFA35999FA93C10Ec746589EB93817a8b9;
    address public dev0Address = 0x2454c7bd6E1Ee62162c97a7E0E2A82D6E1E940AA;
    // address public dev1Address = 0x6d3655EE04820f4385a910FD1898d4Ec6241F520;
    // address public cosmos = address(0xCAAA);
    // address public multisig = address(0);
    address public deployerAddress = 0x58e75944B2B544B8F54C1e6f79eB464b98f0299b;
    // address public priceRouter = address(0);

    // DeFi Ecosystem
    address public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // ERC20s
    ERC20 public USDC = ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    ERC20 public USDCe = ERC20(address(0));
    ERC20 public USDbC = ERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);
    ERC20 public WETH = ERC20(0x4200000000000000000000000000000000000006);
    ERC20 public WBTC = ERC20(0x0555E30da8f98308EdB960aa94C0Db47230d2B9c);
    ERC20 public USDT = ERC20(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2);
    ERC20 public DAI = ERC20(0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb);
    ERC20 public WSTETH = ERC20(0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452);
    ERC20 public cbETH = ERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
    ERC20 public FRAX= ERC20(0x909DBdE1eBE906Af95660033e478D59EFe831fED);
    ERC20 public BAL = ERC20(address(0));
    ERC20 public COMP = ERC20(0x9e1028F5F1D5eDE59748FFceE5532509976840E0);
    ERC20 public LINK = ERC20(0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196);
    ERC20 public rETH = ERC20(0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c);
    ERC20 public LUSD = ERC20(0x368181499736d0c0CC614DBB145E2EC1AC86b8c6);
    ERC20 public UNI = ERC20(address(0));
    ERC20 public CRV = ERC20(address(0));
    ERC20 public FRXETH = ERC20(address(0));
    ERC20 public ARB = ERC20(address(0));
    ERC20 public WEETH = ERC20(address(0));
    ERC20 public AXL_SOMM = ERC20(address(0));

    // Chainlink Datafeeds
    address public BASE_SEQUENCER_UPTIME_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    address public WETH_USD_FEED = address(0);
    address public USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address public USDCe_USD_FEED = address(0);
    address public WBTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
    address public DAI_USD_FEED = 0x591e79239a7d679378eC8c847e5038150364C78F;
    address public USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    address public COMP_USD_FEED = 0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428;
    address public FRAX_USD_FEED = address(0);
    address public WSTETH_ETH_FEED = 0x43a5C292A453A3bF3606fa856197f09D7B74251a;
    address public CBETH_ETH_FEED = 0x806b4Ac04501c29769051e42783cF04dCE41440b;
    address public BAL_USD_FEED = address(0);
    address public LUSD_USD_FEED = address(0);
    address public UNI_USD_FEED = address(0);
    address public CRV_USD_FEED = address(0);
    address public LINK_USD_FEED = 0x17CAb8FE31E32f08326e5E27412894e49B0f9D65;
    address public LINK_ETH_FEED = 0xc5E65227fe3385B88468F9A01600017cDC9F3A12;
    address public MATIC_USD_FEED = 0x12129aAC52D6B0f0125677D4E1435633E61fD25f;
    address public RETH_ETH_FEED = 0xf397bF97280B488cA19ee3093E81C0a77F02e9a5;


    // Aave V3 Tokens
    ERC20 public aV3USDC = ERC20(0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB);
    ERC20 public dV3USDC = ERC20(0x59dca05b6c26dbd64b5381374aAaC5CD05644C28);
    ERC20 public aV3USDbC = ERC20(0x0a1d576f3eFeF75b330424287a95A366e8281D54);
    ERC20 public dV3USDbC = ERC20(0x7376b2F323dC56fCd4C191B34163ac8a84702DAB);
    ERC20 public aV3WETH = ERC20(0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7);
    ERC20 public dV3WETH = ERC20(0x24e6e0795b3c7c71D965fCc4f371803d1c1DcA1E);
    ERC20 public aV3weETH = ERC20(0x7C307e128efA31F540F2E2d976C995E0B65F51F6);
    ERC20 public dV3weETH = ERC20(0x8D2e3F1f4b38AA9f1ceD22ac06019c7561B03901);
    ERC20 public aV3cbBTC = ERC20(0xBdb9300b7CDE636d9cD4AFF00f6F009fFBBc8EE6);
    ERC20 public dV3cbBTC = ERC20(0x05e08702028de6AaD395DC6478b554a56920b9AD);
    ERC20 public aV3WSTETH = ERC20(0x99CBC45ea5bb7eF3a5BC08FB1B7E56bB2442Ef0D);
    ERC20 public dV3WSTETH = ERC20(0x41A7C3f5904ad176dACbb1D99101F59ef0811DC1);
    ERC20 public aV3cbETH = ERC20(0xcf3D55c10DB69f28fD1A75Bd73f3D8A2d9c595ad);
    ERC20 public dV3cbETH = ERC20(0x1DabC36f19909425f654777249815c073E8Fd79F);

    // Balancer V2 Addresses
    address public vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Chainlink Automation Registry
    address public automationRegistry = 0xf4bAb6A129164aBa9B113cB96BA4266dF49f8743;
    address public automationRegistrar = 0xE28Adc50c7551CFf69FCF32D45d037e5F6554264;

    // FraxLend Pairs

    // Curve Pools and Tokens

    // Convex-Curve Platform Specifics

    // 1Inch
    address public oneInchTarget = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    // Uniswap V3
    address public uniswapV3PositionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address public uniswapV3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // 0x
    address public zeroXTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // Redstone

    // Aave V3
    address public aaveV3Pool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address public aaveV3Oracle = 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156;

}
