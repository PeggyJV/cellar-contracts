// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {ERC20Adaptor} from "src/modules/adaptors/ERC20Adaptor.sol";
import {SwapWithUniswapAdaptor} from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import {UniswapV3PositionTracker} from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import {UniswapV3Adaptor} from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import {OneInchAdaptor} from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import {ZeroXAdaptor} from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";
import {UniswapV3Pool} from "src/interfaces/external/UniswapV3Pool.sol";
import {CurveAdaptor} from "src/modules/adaptors/Curve/CurveAdaptor.sol";
import {ConvexCurveAdaptor} from "src/modules/adaptors/Convex/ConvexCurveAdaptor.sol";
import {BalancerPoolAdaptor, SafeTransferLib} from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import {AuraERC4626Adaptor} from "src/modules/adaptors/Aura/AuraERC4626Adaptor.sol";
import {INonfungiblePositionManager} from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import {MorphoBlueSupplyAdaptor} from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import {MorphoBlueDebtAdaptor} from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueDebtAdaptor.sol";
import {MorphoBlueCollateralAdaptor} from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueCollateralAdaptor.sol";
import {EtherFiStakingAdaptor} from "src/modules/adaptors/Staking/EtherFiStakingAdaptor.sol";
import {
    RedstoneEthPriceFeedExtension,
    IRedstoneAdapter
} from "src/modules/price-router/Extensions/Redstone/RedstoneEthPriceFeedExtension.sol";
import {eEthExtension} from "src/modules/price-router/Extensions/EtherFi/eEthExtension.sol";
import {
    BalancerStablePoolExtension,
    IVault
} from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import {IMorpho, MarketParams, Id, Market} from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import {CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport} from
    "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import {ContractDeploymentNames} from "resources/ContractDeploymentNames.sol";
import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626SharePriceOracle} from "src/base/ERC4626SharePriceOracle.sol";
import {FeesAndReservesAdaptor} from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import {FeesAndReserves} from "src/modules/FeesAndReserves.sol";
import {ProtocolFeeCollector} from "src/modules/ProtocolFeeCollector.sol";
import {PositionIds} from "resources/PositionIds.sol";
import {Math} from "src/utils/Math.sol";
import {RolesAuthority, Authority} from "@solmate/auth//authorities/RolesAuthority.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IMB {
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
}
/**
 *  source .env && forge script script/Mainnet/production/SetUpArchitecture.s.sol:SetUpArchitectureScript --evm-version london --with-gas-price 60000000000 --slow --broadcast --etherscan-api-key $MAINNET_RPC_URL --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract SetUpArchitectureScript is Script, MainnetAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Registry public registry;
    PriceRouter public priceRouter;
    address public erc20Adaptor;
    address public swapWithUniswapAdaptor;
    address public uniswapV3Adaptor;
    address public curveAdaptor;
    address public convexCurveAdaptor;
    address public balancerPoolAdaptor;
    address public auraERC4626Adaptor;
    address public oneInchAdaptor;
    address public zeroXAdaptor;
    address public morphoBlueSupplyAdaptor;
    address public morphoBlueDebtAdaptor;
    address public morphoBlueCollateralAdaptor;
    address public etherFiStakingAdaptor;
    address public redstoneEthPriceFeedExtension;
    address public eEthExtensionAddress;
    address public balancerStablePoolExtension;
    uint256 public constant AAVE_V3_MIN_HEALTH_FACTOR = 1.01e18;
    address public feesAndReservesAdaptor;
    address public feesAndReserves;
    address public protocolFeeCollector;
    address public rolesAuthority;

    IMB morphoBlue = IMB(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public pepeEth;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint256 expectedWeEthPriceInUsd8Decimals = 4_087e8;
    uint256 expectedEEthPriceInUsd8Decimals = 3_869e8;
    // uint256 currentPriceOfOneWethWeethBptWith8Decimals = 3_883e8;
    // uint256 currentPriceOfOneRethWeethBptWith8Decimals = 3_883e8;

    bytes32 public weEthWethMarketId = 0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115;

    address public devOwner = 0x59bAE9c3d121152B27A2B5a46bD917574Ca18142;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);
        // Deploy Registry
        registry = new Registry(devOwner, devOwner, address(0), address(0));

        // Deploy Price Router
        priceRouter = new PriceRouter(devOwner, registry, WETH);

        // Update price router in registry.
        registry.setAddress(2, address(priceRouter));

        // Deploy ERC20Adaptor.
        erc20Adaptor = address(new ERC20Adaptor());

        // Deploy SwapWithUniswapAdaptor.
        swapWithUniswapAdaptor = address(new SwapWithUniswapAdaptor(uniV2Router, uniV3Router));

        // Deploy Uniswap V3 Adaptor.
        address tracker = address(new UniswapV3PositionTracker(INonfungiblePositionManager(uniswapV3PositionManager)));

        creationCode = type(UniswapV3Adaptor).creationCode;
        constructorArgs = abi.encode(uniswapV3PositionManager, tracker);
        uniswapV3Adaptor = address(new UniswapV3Adaptor(uniswapV3PositionManager, tracker));

        // Deploy Balancer/Aura Adaptors.
        balancerPoolAdaptor = address(new BalancerPoolAdaptor(vault, minter, 0.9e4));

        auraERC4626Adaptor = address(new AuraERC4626Adaptor());

        // Deploy 1Inch Adaptor.
        oneInchAdaptor = address(new OneInchAdaptor(oneInchTarget));

        // Deploy 0x Adaptor.
        zeroXAdaptor = address(new ZeroXAdaptor(zeroXTarget));

        // Deploy morpho blue adaptors
        morphoBlueSupplyAdaptor = address(new MorphoBlueSupplyAdaptor(_morphoBlue));
        morphoBlueDebtAdaptor = address(new MorphoBlueDebtAdaptor(_morphoBlue, 1.01e18));
        morphoBlueCollateralAdaptor = address(new MorphoBlueCollateralAdaptor(_morphoBlue, 1.01e18));

        // Deploy etherfi staking adaptor
        etherFiStakingAdaptor = address(
            new EtherFiStakingAdaptor(
                address(WETH), 8, liquidityPool, withdrawalRequestNft, address(WEETH), address(EETH)
            )
        );

        // TODO deploy fees and reserves.
        protocolFeeCollector = address(new ProtocolFeeCollector(devOwner));

        feesAndReserves = address(
            new FeesAndReserves(
                protocolFeeCollector,
                0x02777053d6764996e594c3E88AF1D58D5363a2e6,
                0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C
            )
        );
        feesAndReservesAdaptor = address(new FeesAndReservesAdaptor(feesAndReserves));
        // Trust Adaptors in Registry.
        registry.trustAdaptor(erc20Adaptor);
        registry.trustAdaptor(swapWithUniswapAdaptor);
        registry.trustAdaptor(uniswapV3Adaptor);
        registry.trustAdaptor(balancerPoolAdaptor);
        registry.trustAdaptor(auraERC4626Adaptor);
        registry.trustAdaptor(oneInchAdaptor);
        registry.trustAdaptor(zeroXAdaptor);
        registry.trustAdaptor(morphoBlueSupplyAdaptor);
        registry.trustAdaptor(morphoBlueDebtAdaptor);
        registry.trustAdaptor(morphoBlueCollateralAdaptor);
        registry.trustAdaptor(etherFiStakingAdaptor);
        registry.trustAdaptor(feesAndReservesAdaptor);
        // registry.trustAdaptor(curveAdaptor);
        // registry.trustAdaptor(convexCurveAdaptor);

        // Deploy Pricing Extensions.
        redstoneEthPriceFeedExtension = address(new RedstoneEthPriceFeedExtension(priceRouter, address(WETH)));
        eEthExtensionAddress = address(new eEthExtension(priceRouter));
        balancerStablePoolExtension = address(new BalancerStablePoolExtension(priceRouter, IVault(vault)));

        // Add pricing.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        stor.inETH = true;

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = price.mulDivDown(priceRouter.getPriceInUSD(WETH), 1e18);
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        RedstoneEthPriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = weEthDataFeedId;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(weEthEthAdapter);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, redstoneEthPriceFeedExtension);
        priceRouter.addAsset(WEETH, settings, abi.encode(rstor), expectedWeEthPriceInUsd8Decimals);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, eEthExtensionAddress);
        priceRouter.addAsset(EETH, settings, hex"", expectedEEthPriceInUsd8Decimals);

        // TODO Add Balancer pricing
        // BalancerStablePoolExtension.ExtensionStorage memory bstor;

        // bstor = BalancerStablePoolExtension.ExtensionStorage({
        //     poolId: 0xb9debddf1d894c79d2b2d09f819ff9b856fca55200000000000000000000062a,
        //     poolDecimals: 18,
        //     rateProviderDecimals: [uint8(0), 18, 0, 0, 0, 0, 0, 0],
        //     rateProviders: [
        //         address(0),
        //         address(WEETH),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0)
        //     ],
        //     underlyingOrConstituent: [
        //         WETH,
        //         WEETH,
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0))
        //     ]
        // });

        // settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        // priceRouter.addAsset(wEth_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneWethWeethBptWith8Decimals);

        // bstor = BalancerStablePoolExtension.ExtensionStorage({
        //     poolId: 0x05ff47afada98a98982113758878f9a8b9fdda0a000000000000000000000645,
        //     poolDecimals: 18,
        //     rateProviderDecimals: [uint8(18), 18, 0, 0, 0, 0, 0, 0],
        //     rateProviders: [
        //         0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F,
        //         address(WEETH),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0),
        //         address(0)
        //     ],
        //     underlyingOrConstituent: [
        //         rETH,
        //         WEETH,
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0)),
        //         ERC20(address(0))
        //     ]
        // });

        // settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        // priceRouter.addAsset(rETH_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneRethWeethBptWith8Decimals);

        // TODO Add curve pricing

        registry.trustPosition(1, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(2, address(erc20Adaptor), abi.encode(EETH));
        registry.trustPosition(3, address(erc20Adaptor), abi.encode(WEETH));

        registry.trustPosition(
            4, address(uniswapV3Adaptor), abi.encode(address(WETH) < address(WEETH) ? [WETH, WEETH] : [WEETH, WETH])
        );
        _checkTokenOrdering(4);

        registry.trustPosition(
            5, address(uniswapV3Adaptor), abi.encode(address(WEETH) < address(rETH) ? [WEETH, rETH] : [rETH, WEETH])
        );
        _checkTokenOrdering(5);

        registry.trustPosition(
            6, address(uniswapV3Adaptor), abi.encode(address(EETH) < address(WETH) ? [EETH, WETH] : [WETH, EETH])
        );
        _checkTokenOrdering(6);

        registry.trustPosition(
            7, address(uniswapV3Adaptor), abi.encode(address(EETH) < address(rETH) ? [EETH, rETH] : [rETH, EETH])
        );
        _checkTokenOrdering(7);

        // Add Balancer positions
        // TODO find the liquidity gauges
        // registry.trustPosition(8, balancerPoolAdaptor, abi.encode(wEth_weETH_bpt, address(0)));
        // registry.trustPosition(9, balancerPoolAdaptor, abi.encode(rETH_weETH_bpt, address(0)));
        // Add Aura positions
        // registry.trustPosition(10, auraERC4626Adaptor, abi.encode(aura_reth_weeth));

        // Add morpho blue positions
        MarketParams memory weEthWethMarket = morphoBlue.idToMarketParams(weEthWethMarketId);
        // supply positions
        registry.trustPosition(11, address(morphoBlueSupplyAdaptor), abi.encode(weEthWethMarket));

        // collateral positions
        registry.trustPosition(12, address(morphoBlueCollateralAdaptor), abi.encode(weEthWethMarket));

        // borrow positions
        registry.trustPosition(14, address(morphoBlueDebtAdaptor), abi.encode(weEthWethMarket));

        ERC4626SharePriceOracle.ConstructorArgs memory args;
        // Set all oracles to use 50 bps deviation, 5 day TWAAs with 8 hour grace period.
        // Allowed answer change upper and lower of 1.25x and 0.75x
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.005e4;
        args._gracePeriod = 1 days / 3;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devOwner;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.75e4;
        args._allowedAnswerChangeUpper = 1.25e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;

        pepeEth = _createCellarWithNativeSupport(
            "PepeETH", // Name
            "PEPEETH", // Symbol
            WETH,
            1,
            abi.encode(true),
            0.0001e18,
            0.5e18
        );

        args._target = pepeEth;
        _createSharePriceOracle(args);

        args._heartbeat = 300;
        args._gracePeriod = 30 days;

        _createSharePriceOracle(args);

        pepeEth.addAdaptorToCatalogue(erc20Adaptor);
        pepeEth.addAdaptorToCatalogue(swapWithUniswapAdaptor);
        pepeEth.addAdaptorToCatalogue(uniswapV3Adaptor);
        pepeEth.addAdaptorToCatalogue(balancerPoolAdaptor);
        pepeEth.addAdaptorToCatalogue(auraERC4626Adaptor);
        pepeEth.addAdaptorToCatalogue(oneInchAdaptor);
        pepeEth.addAdaptorToCatalogue(zeroXAdaptor);
        pepeEth.addAdaptorToCatalogue(morphoBlueSupplyAdaptor);
        pepeEth.addAdaptorToCatalogue(morphoBlueDebtAdaptor);
        pepeEth.addAdaptorToCatalogue(morphoBlueCollateralAdaptor);
        pepeEth.addAdaptorToCatalogue(etherFiStakingAdaptor);
        pepeEth.addAdaptorToCatalogue(feesAndReservesAdaptor);

        pepeEth.addPositionToCatalogue(2);
        pepeEth.addPositionToCatalogue(3);
        pepeEth.addPositionToCatalogue(4);
        pepeEth.addPositionToCatalogue(5);
        pepeEth.addPositionToCatalogue(6);
        pepeEth.addPositionToCatalogue(7);
        // pepeEth.addPositionToCatalogue(8);
        // pepeEth.addPositionToCatalogue(9);
        // pepeEth.addPositionToCatalogue(10);
        pepeEth.addPositionToCatalogue(11);
        pepeEth.addPositionToCatalogue(12);
        pepeEth.addPositionToCatalogue(14);

        // Deploy RolesAuthority
        rolesAuthority = address(new RolesAuthority(devOwner, Authority(address(0))));

        vm.stopBroadcast();
    }

    function _checkTokenOrdering(uint32 registryId) internal view {
        (,, bytes memory data,) = registry.getPositionIdToPositionData(registryId);
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

    function _createSharePriceOracle(ERC4626SharePriceOracle.ConstructorArgs memory args)
        internal
        returns (ERC4626SharePriceOracle)
    {
        return new ERC4626SharePriceOracle(args);
    }

    function _createCellarWithNativeSupport(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport) {
        // Approve new cellar to spend assets.
        address cellarAddress = 0xD70e70f50365b3b14CB62225BeCdF1d9e893a660;
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        return new CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            devOwner,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(vault)
        );
    }
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (UniswapV3Pool pool);
}
