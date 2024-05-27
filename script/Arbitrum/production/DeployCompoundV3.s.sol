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
import {CompoundV3SupplyAdaptor} from "src/modules/adaptors/Compound/V3/CompoundV3SupplyAdaptor.sol";
import {CompoundV3RewardsAdaptor} from "src/modules/adaptors/Compound/V3/CompoundV3RewardsAdaptor.sol";
import {IComet} from "src/interfaces/external/Compound/IComet.sol";

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
 *  source .env && forge script script/Arbitrum/production/DeployCompoundV3.s.sol:DeployCompoundV3Script --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * If you need to verify contracts after deployment run the following command
 *  source .env && forge script script/Arbitrum/production/DeployCompoundV3.s.sol:DeployCompoundV3Script --evm-version london --etherscan-api-key $ARBISCAN_KEY --verify --resume --rpc-url $ARBITRUM_RPC_URL
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCompoundV3Script is Script, ArbitrumAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    address public cellarOwner = dev0Address;
    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;
    address public compoundV3SupplyAdaptor;
    address public compoundV3RewardsAdaptor;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
    }

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast(privateKey);

        // Deploy Compound V3 Supply Adaptor
        creationCode = type(CompoundV3SupplyAdaptor).creationCode;
        constructorArgs = hex"";
        compoundV3SupplyAdaptor = deployer.deployContract(compoundV3SupplyAdaptorName, creationCode, constructorArgs, 0);

        // Deploy Compound V3 Rewards Adaptor
        creationCode = type(CompoundV3RewardsAdaptor).creationCode;
        constructorArgs = abi.encode(compoundV3Rewards);
        compoundV3RewardsAdaptor =
            deployer.deployContract(compoundV3RewardsAdaptorName, creationCode, constructorArgs, 0);

        registry.trustAdaptor(compoundV3SupplyAdaptor);
        registry.trustAdaptor(compoundV3RewardsAdaptor);

        registry.trustPosition(
            COMPOUND_V3_SUPPLY_USDC_POSITION, compoundV3SupplyAdaptor, abi.encode(compoundV3UsdcComet)
        );
        registry.trustPosition(
            COMPOUND_V3_SUPPLY_USDCE_POSITION, compoundV3SupplyAdaptor, abi.encode(compoundV3UsdceComet)
        );
        vm.stopBroadcast();
    }
}
