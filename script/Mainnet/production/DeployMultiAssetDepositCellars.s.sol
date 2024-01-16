// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/DeployMultiAssetDepositCellars.s.sol:DeployMultiAssetDepositCellarsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMultiAssetDepositCellarsScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public crvUsdCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public morphoBlueCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public stakewiseCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public staderCellar;

    // Positions.
    uint32 wethPositionId = 1;
    uint32 usdcPositionId = 3;

    uint32 crvUsdPositionId = 10000;

    function run() external {
        vm.startBroadcast();

        // Create CRVUSD Cellar.
        crvUsdCellar = _createCellarNoNativeSupport(
            "CRV USD Cellar",
            "CRVUSD CELLAR",
            USDC,
            usdcPositionId,
            abi.encode(0),
            0.01e6,
            0.8e18
        );

        ERC4626SharePriceOracle.ConstructorArgs memory args;
        args._target = crvUsdCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 2;
        args._observationsToUse = 8;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.8e4;
        args._allowedAnswerChangeUpper = 1.2e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("CRV USD Cellar Share Price Oracle V0.0", args);

        crvUsdCellar.transferOwnership(devStrategist);

        // Create Morpho Blue Cellar.
        morphoBlueCellar = _createCellarWithNativeSupport(
            "Morpho Blue Cellar",
            "MB CELLAR",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        args._target = morphoBlueCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.5e4;
        args._allowedAnswerChangeUpper = 3e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("MORPHO BLUE Cellar Share Price Oracle V0.0", args);

        morphoBlueCellar.transferOwnership(devStrategist);

        // Create Stake Wise Cellar.
        stakewiseCellar = _createCellarWithNativeSupport(
            "Stakewise Cellar",
            "SW CELLAR",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        args._target = stakewiseCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.5e4;
        args._allowedAnswerChangeUpper = 3e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("Stakewise Cellar Share Price Oracle V0.0", args);

        stakewiseCellar.transferOwnership(devStrategist);

        // Create Stader Cellar.
        staderCellar = _createCellarWithNativeSupport(
            "Stader Cellar",
            "ST CELLAR",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        args._target = staderCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.5e4;
        args._allowedAnswerChangeUpper = 3e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("Stader Cellar Share Price Oracle V0.0", args);

        staderCellar.transferOwnership(devStrategist);

        vm.stopBroadcast();
    }

    function _createCellarNoNativeSupport(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit).creationCode;
        constructorArgs = abi.encode(
            sommDev,
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
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport).creationCode;
        constructorArgs = abi.encode(
            sommDev,
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
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
                payable(deployer.deployContract(nameToUse, creationCode, constructorArgs, 0))
            );
    }

    function _createSharePriceOracle(
        string memory _name,
        ERC4626SharePriceOracle.ConstructorArgs memory args
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(args);

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
