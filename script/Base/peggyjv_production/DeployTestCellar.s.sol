// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { BaseAddresses } from "test/resources/Base/BaseAddressesPeggyJV.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

import { PositionIds } from "resources/PositionIds.sol";
import { Math } from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Base/peggyjv_production/DeployTestCellar.s.sol:DeployCellarScript --evm-version london --with-gas-price 100000000 --slow --broadcast --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCellarScript is Script, BaseAddresses, ContractDeploymentNames, PositionIds {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdJson for string;

    address public cellarOwner = dev0Address;
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

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");

        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
        erc20Adaptor = deployer.getAddress(erc20AdaptorName);
        swapWithUniswapAdaptor = deployer.getAddress(swapWithUniswapAdaptorName);
        uniswapV3Adaptor = deployer.getAddress(uniswapV3AdaptorName);
        aaveV3ATokenAdaptor = deployer.getAddress(aaveV3ATokenAdaptorName);
        aaveV3DebtTokenAdaptor = deployer.getAddress(aaveV3DebtTokenAdaptorName);
        erc4626Adaptor = deployer.getAddress(erc4626AdaptorName);
        oneInchAdaptor = deployer.getAddress(oneInchAdaptorName);
        zeroXAdaptor = deployer.getAddress(zeroXAdaptorName);
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
        args._sequencerUptimeFeed = BASE_SEQUENCER_UPTIME_FEED;
        args._sequencerGracePeriod = 3_600;
        vm.startBroadcast(privateKey);

        // Deploy cellar.
        RYUSD = _createCellar(
            realYieldUsdName,
            "Real Yield USD",
            "RYUSD",
            USDC,
            ERC20_USDC_POSITION,
            abi.encode(true),
            0.1e6,
            0.8e18
        );

        // Add adaptors.
        RYUSD.addAdaptorToCatalogue(swapWithUniswapAdaptor);
        RYUSD.addAdaptorToCatalogue(uniswapV3Adaptor);
        RYUSD.addAdaptorToCatalogue(aaveV3ATokenAdaptor);
        RYUSD.addAdaptorToCatalogue(aaveV3DebtTokenAdaptor);
        RYUSD.addAdaptorToCatalogue(erc4626Adaptor);
        RYUSD.addAdaptorToCatalogue(oneInchAdaptor);
        RYUSD.addAdaptorToCatalogue(zeroXAdaptor);

        RYUSD.addPositionToCatalogue(ERC20_USDC_POSITION);
        RYUSD.addPositionToCatalogue(ERC20_DAI_POSITION);
        RYUSD.addPositionToCatalogue(ERC20_USDT_POSITION);

        RYUSD.addPositionToCatalogue(AAVE_V3_LOW_HF_A_USDC_POSITION);
        RYUSD.addPositionToCatalogue(AAVE_V3_LOW_HF_DEBT_USDC_POSITION);

        RYUSD.addPositionToCatalogue(UNISWAP_V3_USDC_DAI_POSITION);
        RYUSD.addPositionToCatalogue(UNISWAP_V3_USDC_USDT_POSITION);
        RYUSD.addPositionToCatalogue(UNISWAP_V3_DAI_USDT_POSITION);

        // Create Share Price Oracle.
        args._target = RYUSD;
        ERC4626SharePriceOracle oracle = _createSharePriceOracle(realYieldUsdSharePriceOracleName, args);

        // Register cellar and oracle 
        registry.register(address(RYUSD));
        registry.register(address(oracle));

        // Set the oracle for cellar.
        RYUSD.setSharePriceOracle(4, oracle);

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
    ) internal returns (CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit) {
        // Approve new cellar to spend assets.
        string memory nameToUse = deploymentName;
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit).creationCode;
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
            type(uint192).max,
            address(vault)
        );

        return
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(
                deployer.deployContract(nameToUse, creationCode, constructorArgs, 0)
            );
    }
}
