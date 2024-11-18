// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {ArbitrumAddresses} from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
import {ContractDeploymentNames} from "resources/PeggyJVContractDeploymentNames.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {CellarWithOracle} from "src/base/permutations/CellarWithOracle.sol";
import {ERC4626SharePriceOracle} from "src/base/ERC4626SharePriceOracle.sol";

import {PositionIds} from "resources/PositionIds.sol";
import {Math} from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Arbitrum/peggyjv_production/ExampleDeploy/DeployTestCellar.s.sol:DeployCellarScript --evm-version london --with-gas-price 100000000 --slow --broadcast --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $BASESCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCellarScript is Script, ArbitrumAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    address public cellarOwner = dev0Address;
    uint256 public privateKey;
    
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;

    address public erc20Adaptor;
    address public aaveV3ATokenAdaptor;
    address public aaveV3DebtTokenAdaptor;


    CellarWithOracle public CELLAR;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(base);

        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
        erc20Adaptor = deployer.getAddress(erc20AdaptorName);
        aaveV3ATokenAdaptor = deployer.getAddress(aaveV3ATokenAdaptorName);
        aaveV3DebtTokenAdaptor = deployer.getAddress(aaveV3DebtTokenAdaptorName);
    }

    function run() external {
        ERC4626SharePriceOracle.ConstructorArgs memory args;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.005e4;
        args._gracePeriod = 1 days / 3;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistry;
        args._automationRegistrar = automationRegistrar;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.75e4;
        args._allowedAnswerChangeUpper = 1.25e4;
        args._sequencerUptimeFeed = ARB_SEQUENCER_UPTIME_FEED;
        args._sequencerGracePeriod = 3_600;
        vm.startBroadcast(privateKey);

        // Deploy cellar.
        CELLAR = _createCellar(
            realYieldUsdName,
            "Example cellar",
            "CELLAR",
            USDC,
            ERC20_USDC_POSITION,
            abi.encode(true),
            0.1e6,
            0.8e18
        );

        // Add adaptors.
        CELLAR.addAdaptorToCatalogue(aaveV3ATokenAdaptor);
        CELLAR.addAdaptorToCatalogue(aaveV3DebtTokenAdaptor);

        // Add positions.
        CELLAR.addPositionToCatalogue(ERC20_USDC_POSITION);

        CELLAR.addPositionToCatalogue(AAVE_V3_LOW_HF_A_USDC_POSITION);
        CELLAR.addPositionToCatalogue(AAVE_V3_LOW_HF_DEBT_USDC_POSITION);

        // Create Share Price Oracle.
        args._target = CELLAR;
        ERC4626SharePriceOracle oracle = _createSharePriceOracle(realYieldUsdSharePriceOracleName, args);

        // Register cellar and oracle 
        registry.register(address(CELLAR));
        registry.register(address(oracle));

        // Set the oracle for cellar.
        CELLAR.setSharePriceOracle(4, oracle);

        // Initialize oracle.
        uint96 initialUpkeepFunds = 0.1e18;
        LINK.safeApprove(address(oracle), initialUpkeepFunds);

        oracle.initialize(initialUpkeepFunds);

        vm.stopBroadcast();
    }

    function _createSharePriceOracle(string memory _name, ERC4626SharePriceOracle.ConstructorArgs memory args)
        internal
        returns (ERC4626SharePriceOracle)
    {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(args);

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }

    function _createCellar(
        string memory deploymentName,
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracle) {
        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(deploymentName);
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracle).creationCode;
        constructorArgs = abi.encode(
            cellarOwner,
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

        return
            CellarWithOracle(
                deployer.deployContract(deploymentName, creationCode, constructorArgs, 0)
            );
    }
}
