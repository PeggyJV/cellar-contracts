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
 *  source .env && forge script script/Mainnet/production/DeployTimelocks.s.sol:DeployTimelocksScript --with-gas-price 60000000000 --slow --broadcast --etherscan-api-key $MAINNET_RPC_URL --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract DeployTimelocksScript is Script, MainnetAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    TimelockController private longTimelock;
    TimelockController private shortTimelock;

    address public jointMultisig = address(0);

    address public devOwner = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);

        // Deploy timelock
        uint256 minDelay = 3 days;
        address[] memory proposers = new address[](2);
        proposers[0] = 0x59bAE9c3d121152B27A2B5a46bD917574Ca18142; // crispy
        proposers[1] = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1; // joe
        address[] memory executors = new address[](1);
        executors[0] = jointMultisig;
        longTimelock = new TimelockController(minDelay, proposers, executors, jointMultisig);
        minDelay = 1 days / 4;
        shortTimelock = new TimelockController(minDelay, proposers, executors, jointMultisig);

        vm.stopBroadcast();
    }
}
