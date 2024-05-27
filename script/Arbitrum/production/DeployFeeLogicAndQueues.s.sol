// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {SequencerPriceRouter} from "src/modules/price-router/permutations/SequencerPriceRouter.sol";
import {ArbitrumAddresses} from "test/resources/Arbitrum/ArbitrumAddresses.sol";
import {ContractDeploymentNames} from "resources/ContractDeploymentNames.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {ProtocolFeeCollector} from "src/modules/ProtocolFeeCollector.sol";
import {FeesAndReserves} from "src/modules/FeesAndReserves.sol";
import {FeesAndReservesAdaptor} from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import {WithdrawQueue} from "src/modules/withdraw-queue/WithdrawQueue.sol";
import {SimpleSolver} from "src/modules/withdraw-queue/SimpleSolver.sol";
import {AtomicQueue} from "src/modules/atomic-queue/AtomicQueue.sol";

import {CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit} from
    "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import {CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport} from
    "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import {ERC4626SharePriceOracle} from "src/base/ERC4626SharePriceOracle.sol";

import {PositionIds} from "resources/PositionIds.sol";
import {Math} from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Arbitrum/production/DeployFeeLogicAndQueues.s.sol:DeployFeeLogicAndQueuesScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * If you need to verify contracts after deployment run the following command
 *  source .env && forge script script/Arbitrum/production/DeployFeeLogicAndQueues.s.sol:DeployFeeLogicAndQueuesScript --evm-version london --etherscan-api-key $ARBISCAN_KEY --verify --resume --rpc-url $ARBITRUM_RPC_URL
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployFeeLogicAndQueuesScript is Script, ArbitrumAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    address public cellarOwner = dev0Address;
    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;
    address public protocolFeeCollector;
    address public feesAndReserves;
    address public feesAndReservesAdaptor;
    address public withdrawQueue;
    address public simpleSolver;
    address public atomicQueue;

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public RYE;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
        RYUSD = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(deployer.getAddress(realYieldUsdName));
        RYE = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            payable(deployer.getAddress(realYieldEthName))
        );
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        // Deploy Protocol Fee Collector
        creationCode = type(ProtocolFeeCollector).creationCode;
        constructorArgs = abi.encode(dev0Address);
        protocolFeeCollector = deployer.deployContract(protocolFeeCollectorName, creationCode, constructorArgs, 0);

        // Deploy FeesAndReserves
        creationCode = type(FeesAndReserves).creationCode;
        constructorArgs = abi.encode(protocolFeeCollector, address(0), address(0));
        feesAndReserves = deployer.deployContract(feesAndReservesName, creationCode, constructorArgs, 0);

        // Deploy FeesAndReservesAdaptor
        creationCode = type(FeesAndReservesAdaptor).creationCode;
        constructorArgs = abi.encode(feesAndReserves);
        feesAndReservesAdaptor = deployer.deployContract(feesAndReservesAdaptorName, creationCode, constructorArgs, 0);

        // Deploy WithdrawQueue
        creationCode = type(WithdrawQueue).creationCode;
        constructorArgs = hex"";
        withdrawQueue = deployer.deployContract(withdrawQueueName, creationCode, constructorArgs, 0);

        // Deploy SimpleSolver
        creationCode = type(SimpleSolver).creationCode;
        constructorArgs = abi.encode(withdrawQueue);
        simpleSolver = deployer.deployContract(simpleSolverName, creationCode, constructorArgs, 0);

        // Deploy AtomicQueue
        creationCode = type(AtomicQueue).creationCode;
        constructorArgs = hex"";
        atomicQueue = deployer.deployContract(atomicQueueName, creationCode, constructorArgs, 0);

        registry.trustAdaptor(feesAndReservesAdaptor);

        RYUSD.addAdaptorToCatalogue(feesAndReservesAdaptor);
        RYE.addAdaptorToCatalogue(feesAndReservesAdaptor);

        vm.stopBroadcast();
    }
}
