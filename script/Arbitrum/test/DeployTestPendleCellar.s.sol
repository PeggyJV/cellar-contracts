// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";

import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";

import {ERC4626SharePriceOracle, ERC20} from "src/base/ERC4626SharePriceOracle.sol";
import {CellarWithMultiAssetDeposit, Cellar} from "src/base/permutations/CellarWithMultiAssetDeposit.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {PendleAdaptor, TokenInput, TokenOutput} from "src/modules/adaptors/Pendle/PendleAdaptor.sol";
import {PendleExtension} from "src/modules/price-router/Extensions/Pendle/PendleExtension.sol";

import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";

import {ArbitrumAddresses} from "test/resources/Arbitrum/ArbitrumAddresses.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/test/DeployTestPendleCellar.s.sol:DeployTestPendleCellarScript --evm-version london --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestPendleCellarScript is Script, ArbitrumAddresses {
    using Address for address;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0x43BD96931A47FBABd50727F6982c796B3C9A974C);
    PriceRouter public priceRouter = PriceRouter(0x6aC423c11bb65B1bc7C5Cf292b22e0CBa125f98A);
    PendleExtension private pendleExtension;
    PendleAdaptor private pendleAdaptor;

    address public erc20Adaptor = 0xcaDe581bD66104B278A2F47a43B05a2db64E871f;
    address public zeroXAdaptor = 0x48B11b282964AF32AA26A5f83323271e02E7fAF0;
    address public oneInchAdaptor = 0xc64A77Aad4c9e1d78EaDe6Ad204Df751eCD30173;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint32 public wethPosition = 1;
    uint32 public weethPosition = 6;
    uint32 public pendleLpPosition = 101;
    uint32 public pendleSyPosition = 102;
    uint32 public pendlePtPosition = 103;
    uint32 public pendleYtPosition = 104;

    function run() external {
        vm.startBroadcast();

        // pendleAdaptor = new PendleAdaptor(pendleMarketFactory, pendleRouter);

        // pendleExtension = new PendleExtension(priceRouter, pendleOracle);

        // PriceRouter.ChainlinkDerivativeStorage memory stor;

        // PriceRouter.AssetSettings memory settings;

        // uint256 price = uint256(IChainlinkAggregator(WEETH_ETH_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WEETH_ETH_FEED);
        // priceRouter.addAsset(WEETH, settings, abi.encode(stor), price);

        // // Add pendle pricing.
        // uint256 lpPrice = 7_991e8;
        // uint256 ptPrice = 3_767e8;
        // uint256 ytPrice = 107e8;

        // settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        // PendleExtension.ExtensionStorage memory pstor =
        //     PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarket, 300, WETH);
        // priceRouter.addAsset(ERC20(pendleWeETHMarket), settings, abi.encode(pstor), lpPrice);

        // pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.SY, pendleWeETHMarket, 300, WETH);
        // priceRouter.addAsset(ERC20(pendleWeethSy), settings, abi.encode(pstor), 4_000e8);

        // pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarket, 300, WETH);
        // priceRouter.addAsset(ERC20(pendleEethPt), settings, abi.encode(pstor), ptPrice);

        // pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarket, 300, WETH);
        // priceRouter.addAsset(ERC20(pendleEethYt), settings, abi.encode(pstor), ytPrice);

        // // Deploy Cellar
        // CellarWithMultiAssetDeposit cellar =
        //     _createCellar("PepeEth", "PEP-EETH", WETH, wethPosition, abi.encode(0), 0.01e6, 0.9e18);

        // registry.trustAdaptor(address(pendleAdaptor));
        // registry.trustPosition(weethPosition, address(erc20Adaptor), abi.encode(WEETH));
        // registry.trustPosition(pendleLpPosition, address(erc20Adaptor), abi.encode(pendleWeETHMarket));
        // registry.trustPosition(pendleSyPosition, address(erc20Adaptor), abi.encode(pendleWeethSy));
        // registry.trustPosition(pendlePtPosition, address(erc20Adaptor), abi.encode(pendleEethPt));
        // registry.trustPosition(pendleYtPosition, address(erc20Adaptor), abi.encode(pendleEethYt));

        // cellar.addAdaptorToCatalogue(address(pendleAdaptor));
        // cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        // cellar.addAdaptorToCatalogue(address(oneInchAdaptor));

        // cellar.addPositionToCatalogue(weethPosition);
        // cellar.addPositionToCatalogue(pendleLpPosition);
        // cellar.addPositionToCatalogue(pendleSyPosition);
        // cellar.addPositionToCatalogue(pendlePtPosition);
        // cellar.addPositionToCatalogue(pendleYtPosition);

        CellarWithMultiAssetDeposit cellar = CellarWithMultiAssetDeposit(0xFCe8161bB272a3109498dddd6FdD488C77BCE580);

        cellar.addPosition(1, weethPosition, abi.encode(true), false);
        cellar.addPosition(2, pendleLpPosition, abi.encode(true), false);
        cellar.addPosition(3, pendleSyPosition, abi.encode(true), false);
        cellar.addPosition(4, pendlePtPosition, abi.encode(true), false);
        cellar.addPosition(5, pendleYtPosition, abi.encode(true), false);

        cellar.setAlternativeAssetData(WEETH, weethPosition, 0);

        cellar.transferOwnership(devStrategist);

        vm.stopBroadcast();
    }

    function _createCellar(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithMultiAssetDeposit) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " V0.1");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithMultiAssetDeposit).creationCode;
        constructorArgs = abi.encode(
            dev0Address,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        return CellarWithMultiAssetDeposit(deployer.deployContract(nameToUse, creationCode, constructorArgs, 0));
    }
}
