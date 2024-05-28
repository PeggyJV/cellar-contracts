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
 *  `source .env && forge script script/Mainnet/production/AddPendleAssetsPricing.s.sol:AddPendleAssetsScript --rpc-url $MAINNET_RPC_URL --sender 0xCEA8039076E35a825854c5C2f85659430b06ec96 --with-gas-price 25000000000`
 */

contract AddPendleAssetsScript is Script, MainnetAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Registry public registry = Registry(0x37912f4c0F0d916890eBD755BF6d1f0A0e059BbD);
    PriceRouter public priceRouter = PriceRouter(0x693799805B502264f9365440B93C113D86a4fFF5);
    PendleExtension private pendleExtension = PendleExtension(0x7D43A81e32A2c69e0b8457C815E811Ebe8463E56);
    PendleAdaptor private pendleAdaptor = PendleAdaptor(0x929b041f5E8B71369401d539c1dFFD454D01E439);

    address public erc20Adaptor = 0x7a5b17e0aD1E0F37061fcC7f90512C367981331d;
    RolesAuthority public rolesAuthority = RolesAuthority(0x6a4AbbeE0a07F358c7706C78FD7cC2702fC67D73);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public pepeEth;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    uint8 public constant STRATEGIST_ROLE = 7;
    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant SHORT_TIMELOCK_ROLE = 2;

    address public jointMultisig = address(0);
    uint256 lpSeptemberPrice = 7_735e8;
    uint256 ptSeptemberPrice = 3_728e8;
    uint256 ytSeptemberPrice = 157e8;

    uint256 lpDecemberPrice = 7_479e8;
    uint256 ptDecemberPrice = 3_590e8;
    uint256 ytDecemberPrice = 295e8;

    address public devOwner = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
        pepeEth = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            payable(0xeA1A6307D9b18F8d1cbf1c3Dd6aad8416C06a221)
        );
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast();

        // Add pricing.
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(pendleExtension));

        // Add September Market
        PendleExtension.ExtensionStorage memory pstor =
            PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarketSeptember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeETHMarketSeptember), settings, abi.encode(pstor), lpSeptemberPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarketSeptember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethPtSeptember), settings, abi.encode(pstor), ptSeptemberPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarketSeptember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethYtSeptember), settings, abi.encode(pstor), ytSeptemberPrice);

        // Add December Market.
        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.LP, pendleWeETHMarketDecember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleWeETHMarketDecember), settings, abi.encode(pstor), lpDecemberPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.PT, pendleWeETHMarketDecember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethPtDecember), settings, abi.encode(pstor), ptDecemberPrice);

        pstor = PendleExtension.ExtensionStorage(PendleExtension.PendleAsset.YT, pendleWeETHMarketDecember, 300, EETH);
        priceRouter.addAsset(ERC20(pendleEethYtDecember), settings, abi.encode(pstor), ytDecemberPrice);

        // Also add aweETH to price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        stor.inETH = true;

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WEETH_ETH_FEED);
        uint256 weEthPrice = priceRouter.getPriceInUSD(WEETH);
        priceRouter.addAsset(aV3WeETH, settings, abi.encode(stor), weEthPrice);

        // Add Pendle positions
        // registry.trustPosition(34, address(erc20Adaptor), abi.encode(pendleWeETHMarketSeptember));
        // registry.trustPosition(35, address(erc20Adaptor), abi.encode(pendleEethPtSeptember));
        // registry.trustPosition(36, address(erc20Adaptor), abi.encode(pendleEethYtSeptember));
        // registry.trustPosition(37, address(erc20Adaptor), abi.encode(pendleWeETHMarketDecember));
        // registry.trustPosition(38, address(erc20Adaptor), abi.encode(pendleEethPtDecember));
        // registry.trustPosition(39, address(erc20Adaptor), abi.encode(pendleEethYtDecember));

        vm.stopBroadcast();
    }
}
