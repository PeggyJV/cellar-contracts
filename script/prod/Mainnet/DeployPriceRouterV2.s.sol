// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { PriceRouter, Registry } from "src/base/Cellar.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

// Import adaptors.
import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Mainnet/DeployPriceRouterV2.s.sol:DeployPriceRouterV2Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployPriceRouterV2Script is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private tempOwner = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    // ERC20s
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 public DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 public BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    ERC20 public COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public RETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public CBETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public GHO = ERC20(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public ENS = ERC20(0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72);
    ERC20 public SNX = ERC20(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
    ERC20 public ONEINCH = ERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public LIDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    ERC20 public AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    // Chainlink Datafeeds
    address public WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address public STETH_ETH_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address public fastGasFeed = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    address public FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address public RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address public CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address public LINK_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address public UNI_USD_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address public ENS_USD_FEED = 0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16;
    address public SNX_USD_FEED = 0xDC3EA94CD0AC27d9A86C180091e7f78C683d3699;
    address public ONEINCH_USD_FEED = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;
    address public CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address public LIDO_USD_FEED = 0x4e844125952D32AcdF339BE976c98E22F6F318dB;
    address public MKR_USD_FEED = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;
    address public AAVE_USD_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;

    // Balancer
    IVault private vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ERC20 public BB_A_USD = ERC20(0xc443C15033FCB6Cf72cC24f1BDA0Db070DdD9786);
    ERC20 public GHO_BB_A_USD = ERC20(0xc2B021133D1b0cF07dba696fd5DD89338428225B);

    // Redstone
    bytes32 public ghoDataFeedId;
    address public ghoRedstoneAdapter;

    Registry public registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    PriceRouter private priceRouter;
    WstEthExtension private wstethExtension;
    BalancerStablePoolExtension private balancerStablePoolExtension;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant TWAP_DERIVATIVE = 2;
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    function run() external {
        vm.startBroadcast();

        priceRouter = new PriceRouter(registry, WETH);
        wstethExtension = new WstEthExtension(priceRouter);
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, vault);

        // Add ERC20 assets to the price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price;

        // USD Feeds
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(LINK_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, LINK_USD_FEED);
        priceRouter.addAsset(LINK, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        // ETH Feeds
        stor.inETH = true;
        price = uint256(IChainlinkAggregator(STETH_ETH_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_ETH_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(RETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(CBETH, settings, abi.encode(stor), price);

        // Extensions
        // WSTETH
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // BB_A_USD
        {
            uint8[8] memory rateProviderDecimals;
            address[8] memory rateProviders;
            ERC20[8] memory underlyings;
            underlyings[0] = USDC;
            underlyings[1] = DAI;
            underlyings[2] = USDT;
            BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
                .ExtensionStorage({
                    poolId: bytes32(0),
                    poolDecimals: 18,
                    rateProviderDecimals: rateProviderDecimals,
                    rateProviders: rateProviders,
                    underlyingOrConstituent: underlyings
                });

            settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
            priceRouter.addAsset(BB_A_USD, settings, abi.encode(extensionStor), 1e8);
        }

        // GHO Redstone
        RedstonePriceFeedExtension.ExtensionStorage memory redstoneStor;
        redstoneStor.dataFeedId = ghoDataFeedId;
        redstoneStor.heartbeat = 1 days;
        redstoneStor.redstoneAdapter = IRedstoneAdapter(address(ghoRedstoneAdapter));

        priceRouter.addAsset(GHO, settings, abi.encode(redstoneStor), 1e8);

        // GHO BB_A_USD
        {
            uint8[8] memory rateProviderDecimals;
            address[8] memory rateProviders;
            ERC20[8] memory underlyings;
            underlyings[0] = GHO;
            underlyings[1] = BB_A_USD;
            BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
                .ExtensionStorage({
                    poolId: bytes32(0),
                    poolDecimals: 18,
                    rateProviderDecimals: rateProviderDecimals,
                    rateProviders: rateProviders,
                    underlyingOrConstituent: underlyings
                });

            settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
            priceRouter.addAsset(GHO_BB_A_USD, settings, abi.encode(extensionStor), 1e8);
        }

        vm.stopBroadcast();
    }
}
