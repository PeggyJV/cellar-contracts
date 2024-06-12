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
import {
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport,
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit
} from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import {CellarWithOracle} from "src/base/permutations/CellarWithOracle.sol";
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
import {PendleAdaptor, TokenInput, TokenOutput} from "src/modules/adaptors/Pendle/PendleAdaptor.sol";
import {PendleExtension} from "src/modules/price-router/Extensions/Pendle/PendleExtension.sol";
import {AaveV3ATokenAdaptor} from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import {AaveV3DebtTokenAdaptor} from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import {Cellar} from "src/base/Cellar.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

interface IMB {
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory);
}
/**
 *  source .env && forge script script/Mainnet/production/FinishPepeEthSetup.s.sol:FinishPepeEthSetupScript --with-gas-price 60000000000 --slow --broadcast --etherscan-api-key $MAINNET_RPC_URL --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract FinishPepeEthSetupScript is Script, MainnetAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Registry public registry = Registry(0x37912f4c0F0d916890eBD755BF6d1f0A0e059BbD);
    PriceRouter public priceRouter = PriceRouter(0xAB2d48358D41980eee1cb93764f45148F6818964);
    PendleExtension private pendleExtension;
    PendleAdaptor private pendleAdaptor;
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor;
    TimelockController private timelock;

    address public erc20Adaptor = 0x7a5b17e0aD1E0F37061fcC7f90512C367981331d;
    address public balancerPoolAdaptor = 0xb7D8f4cEAAb784384BbD3B85f6875899C3b8869D;
    address public auraERC4626Adaptor = 0x0F3f8cab8D3888281033faf7A6C0b74dE62bb162;
    address public etherFiStakingAdaptor = 0x08AcC490088045b39dDA3c03e1B57305d9EF9C8A;
    address public balancerStablePoolExtension = 0xf504B437ed0b8ae134D78D8315308eB6Ce0e79F6;
    RolesAuthority public rolesAuthority = RolesAuthority(0x6a4AbbeE0a07F358c7706C78FD7cC2702fC67D73);
    uint256 public constant AAVE_V3_MIN_HEALTH_FACTOR = 1.01e18;

    address private aaveV3Pool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address private aaveOracle = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public pepeEth;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint8 public constant STRATEGIST_ROLE = 7;
    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant SHORT_TIMELOCK_ROLE = 2;

    address public jointMultisig = address(0);
    uint256 currentPriceOfOneWethWeethBptWith8Decimals = 3_756e8;
    uint256 currentPriceOfOneRethWeethBptWith8Decimals = 3_756e8;
    uint256 lpPrice = 7_413e8;
    uint256 ptPrice = 3_497e8;
    uint256 ytPrice = 179e8;

    address public devOwner = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
        pepeEth = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            payable(0xeA1A6307D9b18F8d1cbf1c3Dd6aad8416C06a221)
        );
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);

        // Add pendle support
        pendleAdaptor = new PendleAdaptor(pendleMarketFactory, pendleRouter);
        pendleExtension = new PendleExtension(priceRouter, pendleOracle);

        // Add Aave V3 support.
        aaveV3ATokenAdaptor = new AaveV3ATokenAdaptor(aaveV3Pool, aaveOracle, AAVE_V3_MIN_HEALTH_FACTOR);
        aaveV3DebtTokenAdaptor = new AaveV3DebtTokenAdaptor(aaveV3Pool, AAVE_V3_MIN_HEALTH_FACTOR);

        // Deploy timelock
        // uint256 minDelay = 3 days;
        // address[] memory proposers = new address[](2);
        // proposers[0] = 0x59bAE9c3d121152B27A2B5a46bD917574Ca18142; // crispy
        // proposers[1] = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1; // joe
        // address[] memory executors = new address[](1);
        // executors[0] = jointMultisig;
        // timelock = new TimelockController(minDelay, proposers, executors, jointMultisig);

        // Add pricing.
        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));
        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeETHMarket), settings, abi.encode(pstor), lpPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.SY, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeethSy), settings, abi.encode(pstor), priceRouter.getPriceInUSD(WEETH));

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethPt), settings, abi.encode(pstor), ptPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarket, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethYt), settings, abi.encode(pstor), ytPrice);

        BalancerStablePoolExtension.ExtensionStorage memory bstor;

        bstor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: 0xb9debddf1d894c79d2b2d09f819ff9b856fca55200000000000000000000062a,
            poolDecimals: 18,
            rateProviderDecimals: [uint8(0), 18, 0, 0, 0, 0, 0, 0],
            rateProviders: [
                address(0),
                address(WEETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            underlyingOrConstituent: [
                WETH,
                WEETH,
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0))
            ]
        });

        settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        priceRouter.addAsset(wEth_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneWethWeethBptWith8Decimals);

        bstor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: 0x05ff47afada98a98982113758878f9a8b9fdda0a000000000000000000000645,
            poolDecimals: 18,
            rateProviderDecimals: [uint8(18), 18, 0, 0, 0, 0, 0, 0],
            rateProviders: [
                rethRateProvider,
                address(WEETH),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ],
            underlyingOrConstituent: [
                rETH,
                WEETH,
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0)),
                ERC20(address(0))
            ]
        });

        settings = PriceRouter.AssetSettings({derivative: EXTENSION_DERIVATIVE, source: balancerStablePoolExtension});

        priceRouter.addAsset(rETH_weETH_bpt, settings, abi.encode(bstor), currentPriceOfOneRethWeethBptWith8Decimals);

        // Trust adaptors
        registry.trustAdaptor(address(pendleAdaptor));
        registry.trustAdaptor(address(aaveV3ATokenAdaptor));
        registry.trustAdaptor(address(aaveV3DebtTokenAdaptor));
        // Add Balancer positions
        // This pool currently has no gauge set up.
        registry.trustPosition(8, balancerPoolAdaptor, abi.encode(wEth_weETH_bpt, address(0)));
        registry.trustPosition(9, balancerPoolAdaptor, abi.encode(rETH_weETH_bpt, rETH_weETH_gauge));
        // Add Aura positions
        registry.trustPosition(10, auraERC4626Adaptor, abi.encode(aura_reth_weeth));

        // Add Pendle positions
        registry.trustPosition(15, address(erc20Adaptor), abi.encode(pendleWeETHMarket));
        registry.trustPosition(16, address(erc20Adaptor), abi.encode(pendleWeethSy));
        registry.trustPosition(17, address(erc20Adaptor), abi.encode(pendleEethPt));
        registry.trustPosition(18, address(erc20Adaptor), abi.encode(pendleEethYt));

        // Add unstaking position
        registry.trustPosition(19, etherFiStakingAdaptor, abi.encode(WETH));

        // Add Aave V3 Positions.
        registry.trustPosition(20, address(aaveV3ATokenAdaptor), abi.encode(address(aV3WETH)));
        registry.trustPosition(21, address(aaveV3DebtTokenAdaptor), abi.encode(address(dV3WETH)));

        ERC4626SharePriceOracle.ConstructorArgs memory args;
        args._heartbeat = 2 days;
        args._deviationTrigger = 0.01e4;
        args._gracePeriod = 1 days;
        args._observationsToUse = 3;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devOwner;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.1e4;
        args._allowedAnswerChangeUpper = 10e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;

        args._target = pepeEth;
        _createSharePriceOracle(args);

        pepeEth.addAdaptorToCatalogue(address(pendleAdaptor));
        pepeEth.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        pepeEth.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        pepeEth.addPositionToCatalogue(8);
        pepeEth.addPositionToCatalogue(9);
        pepeEth.addPositionToCatalogue(10);
        pepeEth.addPositionToCatalogue(15);
        pepeEth.addPositionToCatalogue(16);
        pepeEth.addPositionToCatalogue(17);
        pepeEth.addPositionToCatalogue(18);
        pepeEth.addPositionToCatalogue(19);
        pepeEth.addPositionToCatalogue(20);
        pepeEth.addPositionToCatalogue(21);

        // Setup roles
        // Strategist
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.setHoldingPosition.selector, true);
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(pepeEth), Cellar.removePositionFromCatalogue.selector, true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(pepeEth), Cellar.removeAdaptorFromCatalogue.selector, true
        );
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.addPosition.selector, true);
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.removePosition.selector, true);
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.swapPositions.selector, true);
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.initiateShutdown.selector, true);
        rolesAuthority.setRoleCapability(STRATEGIST_ROLE, address(pepeEth), Cellar.callOnAdaptor.selector, true);
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(pepeEth), Cellar.increaseShareSupplyCap.selector, true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(pepeEth), Cellar.decreaseShareSupplyCap.selector, true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(pepeEth),
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.setAlternativeAssetData.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(pepeEth),
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.dropAlternativeAssetData.selector,
            true
        );
        // Admin
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.forcePositionOut.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.setStrategistPlatformCut.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.setStrategistPayoutAddress.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.toggleIgnorePause.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.liftShutdown.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(pepeEth), Cellar.setRebalanceDeviation.selector, true);

        // Short timelock 6-12 hours.
        rolesAuthority.setRoleCapability(
            SHORT_TIMELOCK_ROLE, address(pepeEth), CellarWithOracle.setSharePriceOracle.selector, true
        );
        // Timelock/no role
        // NOTE the timelock is the owner of both Cellar and RolesAuthority, so ALL authorized functions can be called by it,
        // even if not explicilty defined below.
        // cachePriceRouter
        // addPositionToCatalogue
        // addAdaptorToCatalogue

        vm.stopBroadcast();
        // TODO create script to deploy timelocks
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
