// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SequencerPriceRouter } from "src/modules/price-router/permutations/SequencerPriceRouter.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { ERC4626Adaptor } from "src/modules/adaptors/ERC4626Adaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";

import { PositionIds } from "resources/PositionIds.sol";
import { Math } from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Arbitrum/peggyjv_production/ExampleDeploy/SetUpArchitecture.s.sol:SetUpArchitectureScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SetUpArchitectureScript is Script, ArbitrumAddresses, ContractDeploymentNames, PositionIds {
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;
    
    address public erc20Adaptor;
    address public aaveV3ATokenAdaptor;
    address public aaveV3DebtTokenAdaptor;

    uint256 public constant AAVE_V3_MIN_HEALTH_FACTOR = 1.01e18;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.createSelectFork("arbitrum");
        vm.startBroadcast(privateKey);
        // Deploy Registry
        creationCode = type(Registry).creationCode;
        constructorArgs = abi.encode(dev0Address, dev0Address, address(0), address(0));
        registry = Registry(deployer.deployContract(registryName, creationCode, constructorArgs, 0));

        // Deploy Price Router
        creationCode = type(SequencerPriceRouter).creationCode;
        constructorArgs = abi.encode(ARB_SEQUENCER_UPTIME_FEED, uint256(3_600), dev0Address, registry, WETH);
        priceRouter = PriceRouter(deployer.deployContract(priceRouterName, creationCode, constructorArgs, 0));

        // Update price router in registry.
        registry.setAddress(2, address(priceRouter));

        // Deploy ERC20Adaptor.
        creationCode = type(ERC20Adaptor).creationCode;
        constructorArgs = hex"";
        erc20Adaptor = deployer.deployContract(erc20AdaptorName, creationCode, constructorArgs, 0);


        // Deploy Aave V3 Adaptors.
        creationCode = type(AaveV3ATokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, aaveV3Oracle, AAVE_V3_MIN_HEALTH_FACTOR);
        aaveV3ATokenAdaptor = deployer.deployContract(aaveV3ATokenAdaptorName, creationCode, constructorArgs, 0);

        creationCode = type(AaveV3DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, AAVE_V3_MIN_HEALTH_FACTOR);
        aaveV3DebtTokenAdaptor = deployer.deployContract(aaveV3DebtTokenAdaptorName, creationCode, constructorArgs, 0);

        // Trust Adaptors in Registry.
        registry.trustAdaptor(erc20Adaptor);
        registry.trustAdaptor(aaveV3ATokenAdaptor);
        registry.trustAdaptor(aaveV3DebtTokenAdaptor);
        // Add pricing.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);



        // Add ERC20 positions.
        registry.trustPosition(ERC20_USDC_POSITION, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(ERC20_WETH_POSITION, address(erc20Adaptor), abi.encode(WETH));
        

        // Add Aave V3 a token positions.
        registry.trustPosition(AAVE_V3_LOW_HF_A_USDC_POSITION, address(aaveV3ATokenAdaptor), abi.encode(aV3USDC));
        registry.trustPosition(AAVE_V3_LOW_HF_A_WETH_POSITION, address(aaveV3ATokenAdaptor), abi.encode(aV3WETH));

        // Add Aave V3 debt token.
        registry.trustPosition(AAVE_V3_LOW_HF_DEBT_USDC_POSITION, address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDC));
        registry.trustPosition(AAVE_V3_LOW_HF_DEBT_WETH_POSITION, address(aaveV3DebtTokenAdaptor), abi.encode(dV3WETH));

        vm.stopBroadcast();
    }

}
