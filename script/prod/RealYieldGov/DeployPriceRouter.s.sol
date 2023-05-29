// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry, PriceRouter, Math, ERC20 } from "src/base/Cellar.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldGov/DeployPriceRouter.s.sol:DeployPriceRouterScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployPriceRouterScript is Script {
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public ONEINCH = ERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public SNX = ERC20(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
    ERC20 public ENS = ERC20(0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    ERC20 public AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    ERC20 public LDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);
    ERC20 public WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    address public WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public LINK_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address public ONEINCH_USD_FEED = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;
    address public UNI_USD_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address public SNX_USD_FEED = 0xDC3EA94CD0AC27d9A86C180091e7f78C683d3699;
    address public ENS_USD_FEED = 0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16;
    address public CRV_USD_FEED = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;
    address public STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address public STETH_ETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address public MKR_USD_FEED = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;
    address public AAVE_USD_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public LDO_ETH_FEED = 0x4e844125952D32AcdF339BE976c98E22F6F318dB;
    address public RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address public CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address public WSTETH_ETH_FEED = 0xD9FD7dD08b3fFC53323dB881661367e0D16a71C7;

    PriceRouter private priceRouter = PriceRouter(0x545Ce2e5b603c260cC6b2D1B78A66404E12590d8);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);

    function run() external {
        vm.startBroadcast();

        // Add required assets to price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        // uint256 price = uint256(IChainlinkAggregator(CRV_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CRV_USD_FEED);
        // priceRouter.addAsset(CRV, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        // priceRouter.addAsset(stETH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(MKR_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, MKR_USD_FEED);
        // priceRouter.addAsset(MKR, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(AAVE_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, AAVE_USD_FEED);
        // priceRouter.addAsset(AAVE, settings, abi.encode(stor), price);

        stor.inETH = true;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_ETH_FEED);
        uint256 price = uint256(IChainlinkAggregator(STETH_ETH_FEED).latestAnswer());
        price = priceRouter.getValue(WETH, price, USDC).changeDecimals(6, 8);
        priceRouter.addAsset(stETH, settings, abi.encode(stor), price);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        // price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        // price = priceRouter.getValue(WETH, price, USDC).changeDecimals(6, 8);
        // priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        // price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        // price = priceRouter.getValue(WETH, price, USDC).changeDecimals(6, 8);
        // priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WSTETH_ETH_FEED);
        // stor = PriceRouter.ChainlinkDerivativeStorage(80e18, 0.1e18, 0, true);
        // price = uint256(IChainlinkAggregator(WSTETH_ETH_FEED).latestAnswer());
        // price = priceRouter.getValue(WETH, price, USDC).changeDecimals(6, 8);
        // priceRouter.addAsset(WSTETH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        // priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        // priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(LINK_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, LINK_USD_FEED);
        // priceRouter.addAsset(LINK, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(ONEINCH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ONEINCH_USD_FEED);
        // priceRouter.addAsset(ONEINCH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(UNI_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, UNI_USD_FEED);
        // priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(SNX_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, SNX_USD_FEED);
        // priceRouter.addAsset(SNX, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(ENS_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ENS_USD_FEED);
        // priceRouter.addAsset(ENS, settings, abi.encode(stor), price);
        // vm.stopBroadcast();
    }
}
