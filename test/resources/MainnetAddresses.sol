// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CErc20 } from "src/interfaces/external/ICompound.sol";

contract MainnetAddresses {
    // Sommelier
    address public gravityBridgeAddress = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address public strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address public testStrategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address public cosmos = address(0xCAAA);
    address public multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address public ryusdRegistry = 0x2Cbd27E034FEE53f79b607430dA7771B22050741;
    address public ryusdRegistryOwner = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;
    address public deployerAddress = 0x70832E3e9a3268Fe9A5a47803e945fC34280B976;
    address public priceRouterV1 = 0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA;
    address public priceRouterV2 = 0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92;
    address public ryusdAddress = 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E;

    // DeFi Ecosystem
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // ERC20s
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 public TUSD = ERC20(0x0000000000085d4780B73119b644AE5ecd22b376);
    ERC20 public DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 public BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 public COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public RPL = ERC20(0xD33526068D116cE69F19A9ee46F0bd304F21A51f);
    ERC20 public BOND = ERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);
    ERC20 public SWETH = ERC20(0xf951E335afb289353dc249e82926178EaC7DEd78);
    ERC20 public GHO = ERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
    ERC20 public LUSD = ERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    ERC20 public OHM = ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    ERC20 public APE = ERC20(0x4d224452801ACEd8B2F0aebE155379bb5D594381);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 public FRXETH = ERC20(0x5E8422345238F34275888049021821E8E08CAa1f);

    // Chainlink Datafeeds
    address public WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public TUSD_USD_FEED = 0xec746eCF986E2927Abd291a2A1716c940100f8Ba;
    address public STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address public fastGasFeed = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    address public FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address public RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address public BOND_ETH_FEED = 0xdd22A54e05410D8d1007c38b5c7A3eD74b855281;
    address public CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address public STETH_ETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public GHO_USD_FEED = 0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC;
    address public LUSD_USD_FEED = 0x3D7aE7E594f2f2091Ad8798313450130d0Aba3a0;
    address public OHM_ETH_FEED = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address public MKR_USD_FEED = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;
    address public UNI_ETH_FEED = 0xD6aA3D25116d8dA79Ea0246c4826EB951872e02e;
    address public APE_USD_FEED = 0xD10aBbC76679a20055E167BB80A24ac851b37056;
    address public CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address public CVX_USD_FEED = 0xd962fC30A72A84cE50161031391756Bf2876Af5D;
    address public CVX_ETH_FEED = 0xC9CbF687f43176B302F03f5e58470b77D07c61c6;

    // Aave V2 Tokens
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public aV2USDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 public dV2USDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 public aV2WBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 public aV2TUSD = ERC20(0x101cc05f4A51C0319f570d5E146a8C625198e636);
    ERC20 public aV2STETH = ERC20(0x1982b2F5814301d4e9a8b0201555376e62F82428);
    ERC20 public aV2DAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    ERC20 public dV2DAI = ERC20(0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d);
    ERC20 public aV2USDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);
    ERC20 public dV2USDT = ERC20(0x531842cEbbdD378f8ee36D171d6cC9C4fcf475Ec);

    // Aave V3 Tokens
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public aV3USDC = ERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    ERC20 public dV3USDC = ERC20(0x72E95b8931767C79bA4EeE721354d6E99a61D004);
    ERC20 public aV3DAI = ERC20(0x018008bfb33d285247A21d44E50697654f754e63);
    ERC20 public dV3DAI = ERC20(0xcF8d0c70c850859266f5C338b38F9D663181C314);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3WBTC = ERC20(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);
    ERC20 public aV3USDT = ERC20(0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a);
    ERC20 public dV3USDT = ERC20(0x6df1C1E379bC5a00a7b4C6e67A203333772f45A8);
    ERC20 public aV3sDAI = ERC20(0x4C612E3B15b96Ff9A6faED838F8d07d479a8dD4c);

    // Balancer V2 Addresses
    ERC20 public BB_A_USD = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    ERC20 public BB_A_USD_V3 = ERC20(0xc443C15033FCB6Cf72cC24f1BDA0Db070DdD9786);
    ERC20 public vanillaUsdcDaiUsdt = ERC20(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);
    ERC20 public BB_A_WETH = ERC20(0x60D604890feaa0b5460B28A424407c24fe89374a);
    ERC20 public wstETH_bbaWETH = ERC20(0xE0fCBf4d98F0aD982DB260f86cf28b49845403C5);
    ERC20 public new_wstETH_bbaWETH = ERC20(0x41503C9D499ddbd1dCdf818a1b05e9774203Bf46);
    ERC20 public GHO_LUSD_BPT = ERC20(0x3FA8C89704e5d07565444009e5d9e624B40Be813);
    ERC20 public swETH_bbaWETH = ERC20(0xaE8535c23afeDdA9304B03c68a3563B75fc8f92b);
    ERC20 public swETH_wETH = ERC20(0x02D928E68D8F10C0358566152677Db51E1e2Dc8C);

    // Linear Pools.
    ERC20 public bb_a_dai = ERC20(0x6667c6fa9f2b3Fc1Cc8D85320b62703d938E4385);
    ERC20 public bb_a_usdt = ERC20(0xA1697F9Af0875B63DdC472d6EeBADa8C1fAB8568);
    ERC20 public bb_a_usdc = ERC20(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);

    ERC20 public BB_A_USD_GAUGE = ERC20(0x0052688295413b32626D226a205b95cDB337DE86); // query subgraph for gauges wrt to poolId: https://docs.balancer.fi/reference/vebal-and-gauges/gauges.html#query-gauge-by-l2-sidechain-pool:~:text=%23-,Query%20Pending%20Tokens%20for%20a%20Given%20Pool,-The%20process%20differs
    address public BB_A_USD_GAUGE_ADDRESS = 0x0052688295413b32626D226a205b95cDB337DE86;
    address public wstETH_bbaWETH_GAUGE_ADDRESS = 0x5f838591A5A8048F0E4C4c7fCca8fD9A25BF0590;

    // Mainnet Balancer Specific Addresses
    address public vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public relayer = 0xfeA793Aa415061C483D2390414275AD314B3F621;
    address public minter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
    ERC20 public USDC_DAI_USDT_BPT = ERC20(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);
    ERC20 public rETH_wETH_BPT = ERC20(0x1E19CF2D73a72Ef1332C882F20534B6519Be0276);
    ERC20 public wstETH_wETH_BPT = ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ERC20 public wstETH_cbETH_BPT = ERC20(0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2);
    ERC20 public bb_a_USD_BPT = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    ERC20 public bb_a_USDC_BPT = ERC20(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);
    ERC20 public bb_a_DAI_BPT = ERC20(0x6667c6fa9f2b3Fc1Cc8D85320b62703d938E4385);
    ERC20 public bb_a_USDT_BPT = ERC20(0xA1697F9Af0875B63DdC472d6EeBADa8C1fAB8568);
    ERC20 public GHO_bb_a_USD_BPT = ERC20(0xc2B021133D1b0cF07dba696fd5DD89338428225B);

    // Rate Providers
    address public cbethRateProvider = 0x7311E4BB8a72e7B300c5B8BDE4de6CdaA822a5b1;
    address public rethRateProvider = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;

    // Compound V2
    CErc20 public cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    CErc20 public cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    CErc20 public cTUSD = CErc20(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);

    // Chainlink Automation Registry
    address public automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;

    // FraxLend Pairs
    address public FXS_FRAX_PAIR = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address public FPI_FRAX_PAIR = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
    address public SFRXETH_FRAX_PAIR = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;
    address public CRV_FRAX_PAIR = 0x3835a58CA93Cdb5f912519ad366826aC9a752510; // FraxlendV1
    address public WBTC_FRAX_PAIR = 0x32467a5fc2d72D21E8DCe990906547A2b012f382; // FraxlendV1
    address public WETH_FRAX_PAIR = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff; // FraxlendV1
    address public CVX_FRAX_PAIR = 0xa1D100a5bf6BFd2736837c97248853D989a9ED84; // FraxlendV1
    address public MKR_FRAX_PAIR = 0x82Ec28636B77661a95f021090F6bE0C8d379DD5D; // FraxlendV2
    address public APE_FRAX_PAIR = 0x3a25B9aB8c07FfEFEe614531C75905E810d8A239; // FraxlendV2
    address public UNI_FRAX_PAIR = 0xc6CadA314389430d396C7b0C70c6281e99ca7fe8; // FraxlendV2

    // Curve Pools and Tokens
    address public TriCryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    ERC20 public CRV_3_CRYPTO = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    address public daiUsdcUsdtPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    ERC20 public CRV_DAI_USDC_USDT = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address public frax3CrvPool = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    ERC20 public CRV_FRAX_3CRV = ERC20(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address public wethCrvPool = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    ERC20 public CRV_WETH_CRV = ERC20(0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d);
    address public aave3Pool = 0xDeBF20617708857ebe4F679508E7b7863a8A8EeE;
    ERC20 public CRV_AAVE_3CRV = ERC20(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);
    address public stETHWethNg = 0x21E27a5E5513D6e65C4f830167390997aA84843a;

    // Uniswap V3
    address public WSTETH_WETH_100 = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address public WSTETH_WETH_500 = 0xD340B57AAcDD10F96FC1CF10e15921936F41E29c;
    address public DAI_USDC_100 = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;

    // Redstone
    address public swEthAdapter = 0x68ba9602B2AeE30847412109D2eE89063bf08Ec2;
    bytes32 public swEthDataFeedId = 0x5357455448000000000000000000000000000000000000000000000000000000;
    // Maker
    address public dsrManager = 0x373238337Bfe1146fb49989fc222523f83081dDb;

    // Current Active Cellars
    address public ryusdCellar = 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E;

    // Maker
    address public savingsDaiAddress = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    // Curve
    address public EthFrxEthCurvePool = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
}
