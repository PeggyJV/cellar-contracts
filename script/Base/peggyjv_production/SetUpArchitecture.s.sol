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
import { BaseAddresses} from "test/resources/Base/BaseAddressesPeggyJV.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";

import { PositionIds } from "resources/PositionIds.sol";
import { Math } from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Base/peggyjv_production/SetUpArchitecture.s.sol:SetUpArchitectureScript --rpc-url $BASE_RPC_URL --with-gas-price 100000000 --slow --broadcast
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SetUpArchitectureScript is Script, BaseAddresses, ContractDeploymentNames, PositionIds {
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;
    address public erc20Adaptor;
    address public swapWithUniswapAdaptor;
    address public uniswapV3Adaptor;
    address public aaveV3ATokenAdaptor;
    address public aaveV3DebtTokenAdaptor;
    address public erc4626Adaptor;
    address public oneInchAdaptor;
    address public zeroXAdaptor;

    uint256 public constant AAVE_V3_MIN_HEALTH_FACTOR = 1.01e18;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    function setUp() external {
        privateKey = vm.envUint("DEV0_PRIVATE_KEY");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.createSelectFork("base");
        vm.startBroadcast(privateKey);
        // Deploy Registry
        creationCode = type(Registry).creationCode;
        constructorArgs = abi.encode(dev0Address, dev0Address, address(0), address(0));
        registry = Registry(deployer.deployContract(registryName, creationCode, constructorArgs, 0));

        // Deploy Price Router
        creationCode = type(SequencerPriceRouter).creationCode;
        constructorArgs = abi.encode(BASE_SEQUENCER_UPTIME_FEED, uint256(3_600), dev0Address, registry, WETH);
        priceRouter = PriceRouter(deployer.deployContract(priceRouterName, creationCode, constructorArgs, 0));

        // Update price router in registry.
        registry.setAddress(2, address(priceRouter));

        // Deploy ERC20Adaptor.
        creationCode = type(ERC20Adaptor).creationCode;
        constructorArgs = hex"";
        erc20Adaptor = deployer.deployContract(erc20AdaptorName, creationCode, constructorArgs, 0);

        // Deploy SwapWithUniswapAdaptor.
        creationCode = type(SwapWithUniswapAdaptor).creationCode;
        constructorArgs = abi.encode(uniV2Router, uniV3Router);
        swapWithUniswapAdaptor = deployer.deployContract(swapWithUniswapAdaptorName, creationCode, constructorArgs, 0);

        // Deploy Uniswap V3 Adaptor.
        creationCode = type(UniswapV3PositionTracker).creationCode;
        constructorArgs = abi.encode(uniswapV3PositionManager);
        address tracker = deployer.deployContract(uniswapV3PositionTrackerName, creationCode, constructorArgs, 0);

        creationCode = type(UniswapV3Adaptor).creationCode;
        constructorArgs = abi.encode(uniswapV3PositionManager, tracker);
        uniswapV3Adaptor = deployer.deployContract(uniswapV3AdaptorName, creationCode, constructorArgs, 0);

        // Deploy Aave V3 Adaptors.
        creationCode = type(AaveV3ATokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, aaveV3Oracle, AAVE_V3_MIN_HEALTH_FACTOR);
        aaveV3ATokenAdaptor = deployer.deployContract(aaveV3ATokenAdaptorName, creationCode, constructorArgs, 0);

        creationCode = type(AaveV3DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(aaveV3Pool, AAVE_V3_MIN_HEALTH_FACTOR);
        aaveV3DebtTokenAdaptor = deployer.deployContract(aaveV3DebtTokenAdaptorName, creationCode, constructorArgs, 0);

        // Deploy ERC4626 Adaptor.
        creationCode = type(ERC4626Adaptor).creationCode;
        constructorArgs = hex"";
        erc4626Adaptor = deployer.deployContract(erc4626AdaptorName, creationCode, constructorArgs, 0);

        // Deploy 1Inch Adaptor.
        creationCode = type(OneInchAdaptor).creationCode;
        constructorArgs = abi.encode(oneInchTarget);
        oneInchAdaptor = deployer.deployContract(oneInchAdaptorName, creationCode, constructorArgs, 0);

        // Deploy 0x Adaptor.
        creationCode = type(ZeroXAdaptor).creationCode;
        constructorArgs = abi.encode(zeroXTarget);
        zeroXAdaptor = deployer.deployContract(zeroXAdaptorName, creationCode, constructorArgs, 0);

        // Trust Adaptors in Registry.
        registry.trustAdaptor(erc20Adaptor);
        registry.trustAdaptor(swapWithUniswapAdaptor);
        registry.trustAdaptor(uniswapV3Adaptor);
        registry.trustAdaptor(aaveV3ATokenAdaptor);
        registry.trustAdaptor(aaveV3DebtTokenAdaptor);
        registry.trustAdaptor(erc4626Adaptor);
        registry.trustAdaptor(oneInchAdaptor);
        registry.trustAdaptor(zeroXAdaptor);

        // Add pricing.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);


        // Add ERC20 positions.
        registry.trustPosition(ERC20_USDC_POSITION, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(ERC20_DAI_POSITION, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(ERC20_USDT_POSITION, address(erc20Adaptor), abi.encode(USDT));

        // Add Aave V3 a token positions.
        registry.trustPosition(AAVE_V3_LOW_HF_A_USDC_POSITION, address(aaveV3ATokenAdaptor), abi.encode(aV3USDC));

        // Add Aave V3 debt token positions.
        registry.trustPosition(AAVE_V3_LOW_HF_DEBT_USDC_POSITION, address(aaveV3DebtTokenAdaptor), abi.encode(dV3USDC));
        
        // Add Uniswap V3 positions.
        registry.trustPosition(
            UNISWAP_V3_USDC_DAI_POSITION,
            address(uniswapV3Adaptor),
            abi.encode(address(USDC) < address(DAI) ? [USDC, DAI] : [DAI, USDC])
        );
        _checkTokenOrdering(UNISWAP_V3_USDC_DAI_POSITION);

        registry.trustPosition(
            UNISWAP_V3_USDC_USDT_POSITION,
            address(uniswapV3Adaptor),
            abi.encode(address(USDC) < address(USDT) ? [USDC, USDT] : [USDT, USDC])
        );
        _checkTokenOrdering(UNISWAP_V3_USDC_USDT_POSITION);

        registry.trustPosition(
            UNISWAP_V3_DAI_USDT_POSITION,
            address(uniswapV3Adaptor),
            abi.encode(address(DAI) < address(USDT) ? [DAI, USDT] : [USDT, DAI])
        );
        _checkTokenOrdering(UNISWAP_V3_DAI_USDT_POSITION);

    }

    function _checkTokenOrdering(uint32 registryId) internal view {
        (, , bytes memory data, ) = registry.getPositionIdToPositionData(registryId);
        (address token0, address token1) = abi.decode(data, (address, address));
        if (token1 < token0) revert("Tokens out of order");
        UniswapV3Pool pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 100);
        if (address(pool) == address(0)) pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 500);
        if (address(pool) == address(0)) pool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, 3000);
        if (address(pool) != address(0)) {
            if (pool.token0() != token0) revert("Token 0 mismtach");
            if (pool.token1() != token1) revert("Token 1 mismtach");
        }
    }
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (UniswapV3Pool pool);
}
