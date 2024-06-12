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
import {CellarStaking} from "src/modules/staking/CellarStaking.sol";

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
 *  source .env && forge script script/Arbitrum/production/AddCompoundV3SupplyAndDeployStakingContractsForRYProducts.s.sol:AddCompoundV3SupplyAndDeployStakingContractsForRYProductsScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * If you need to verify contracts after deployment run the following command
 *  source .env && forge script script/Arbitrum/production/AddCompoundV3SupplyAndDeployStakingContractsForRYProducts.s.sol:AddCompoundV3SupplyAndDeployStakingContractsForRYProductsScript --evm-version london --etherscan-api-key $ARBISCAN_KEY --verify --resume --rpc-url $ARBITRUM_RPC_URL
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract AddCompoundV3SupplyAndDeployStakingContractsForRYProductsScript is
    Script,
    ArbitrumAddresses,
    ContractDeploymentNames,
    PositionIds
{
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

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public RYE;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
        compoundV3SupplyAdaptor = deployer.getAddress(compoundV3SupplyAdaptorName);
        compoundV3RewardsAdaptor = deployer.getAddress(compoundV3RewardsAdaptorName);
        RYUSD = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(deployer.getAddress(realYieldUsdName));
        RYE = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            payable(deployer.getAddress(realYieldEthName))
        );
    }

    function run() external {
        vm.startBroadcast(privateKey);

        // Setup Compound V3 in RYUSD.
        RYUSD.addAdaptorToCatalogue(compoundV3SupplyAdaptor);
        RYUSD.addAdaptorToCatalogue(compoundV3RewardsAdaptor);
        RYUSD.addPositionToCatalogue(COMPOUND_V3_SUPPLY_USDC_POSITION);
        RYUSD.addPositionToCatalogue(COMPOUND_V3_SUPPLY_USDCE_POSITION);

        // Deploy staking adaptors.
        _createStakingContract(RYUSD, realYieldUsdStakingName);
        _createStakingContract(RYE, realYieldEthStakingName);

        vm.stopBroadcast();
    }

    function _createStakingContract(ERC20 _stakingToken, string memory _name) internal returns (CellarStaking) {
        bytes memory creationCode;
        bytes memory constructorArgs;

        address _owner = devStrategist;
        ERC20 _distributionToken = AXL_SOMM;
        uint256 _epochDuration = 3 days;
        uint256 shortBoost = 0.1e18;
        uint256 mediumBoost = 0.3e18;
        uint256 longBoost = 0.5e18;
        uint256 shortBoostTime = 7 days;
        uint256 mediumBoostTime = 14 days;
        uint256 longBoostTime = 21 days;

        // Deploy the staking contract.
        creationCode = type(CellarStaking).creationCode;
        constructorArgs = abi.encode(
            _owner,
            _stakingToken,
            _distributionToken,
            _epochDuration,
            shortBoost,
            mediumBoost,
            longBoost,
            shortBoostTime,
            mediumBoostTime,
            longBoostTime
        );
        return CellarStaking(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
