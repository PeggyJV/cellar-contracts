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

import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";

import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { MorphoAaveV2ATokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployLowerHFAdaptors.s.sol:DeployLowerHFAdaptorsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployLowerHFAdaptorsScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

    address public v2Pool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address public v3Pool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public v3Oracle = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    address public morphoV2 = 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0;
    address public morphoLens = 0x507fA343d0A90786d86C7cd885f5C49263A91FF4;
    address public rewardsDistributor = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;

    address public morphoV3 = 0x33333aea097c193e66081E930c33020272b33333;

    CellarWithOracleWithBalancerFlashLoans public stethCellar;
    AaveATokenAdaptor public aaveATokenAdaptor;
    AaveDebtTokenAdaptor public aaveDebtTokenAdaptor;
    AaveV3ATokenAdaptor public aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor public aaveV3DebtTokenAdaptor;
    MorphoAaveV2ATokenAdaptor public morphoAaveV2ATokenAdaptor;
    MorphoAaveV2DebtTokenAdaptor public morphoAaveV2DebtTokenAdaptor;
    MorphoAaveV3ATokenCollateralAdaptor public morphoAaveV3ATokenCollateralAdaptor;
    MorphoAaveV3DebtTokenAdaptor public morphoAaveV3DebtTokenAdaptor;

    uint256 hfMin = 1.02e18;

    function run() external {
        vm.startBroadcast();

        stethCellar = CellarWithOracleWithBalancerFlashLoans(0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971);

        bytes memory creationCode;
        bytes memory constructorArgs;

        creationCode = type(AaveATokenAdaptor).creationCode;
        constructorArgs = abi.encode(v2Pool, WETH, hfMin);
        aaveATokenAdaptor = AaveATokenAdaptor(
            deployer.deployContract("Aave aToken Adaptor V 1.4", creationCode, constructorArgs, 0)
        );

        creationCode = type(AaveDebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(v2Pool, hfMin);
        aaveDebtTokenAdaptor = AaveDebtTokenAdaptor(
            deployer.deployContract("Aave debtToken Adaptor V 1.3", creationCode, constructorArgs, 0)
        );

        creationCode = type(AaveV3ATokenAdaptor).creationCode;
        constructorArgs = abi.encode(v3Pool, v3Oracle, hfMin);
        aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(
            deployer.deployContract("Aave V3 aToken Adaptor V 1.3", creationCode, constructorArgs, 0)
        );

        creationCode = type(AaveV3DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(v3Pool, hfMin);
        aaveV3DebtTokenAdaptor = AaveV3DebtTokenAdaptor(
            deployer.deployContract("Aave V3 debtToken Adaptor V 1.2", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoAaveV2ATokenAdaptor).creationCode;
        constructorArgs = abi.encode(morphoV2, morphoLens, hfMin, rewardsDistributor);
        morphoAaveV2ATokenAdaptor = MorphoAaveV2ATokenAdaptor(
            deployer.deployContract("Morpho Aave V2 aToken Adaptor V 1.3", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoAaveV2DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(morphoV2, morphoLens, hfMin);
        morphoAaveV2DebtTokenAdaptor = MorphoAaveV2DebtTokenAdaptor(
            deployer.deployContract("Morpho Aave V2 debtToken Adaptor V 1.2", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoAaveV3ATokenCollateralAdaptor).creationCode;
        constructorArgs = abi.encode(morphoV3, hfMin, rewardsDistributor);
        morphoAaveV3ATokenCollateralAdaptor = MorphoAaveV3ATokenCollateralAdaptor(
            deployer.deployContract("Morpho Aave V3 aToken Collateral Adaptor V 1.3", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoAaveV3DebtTokenAdaptor).creationCode;
        constructorArgs = abi.encode(morphoV3, hfMin);
        morphoAaveV3DebtTokenAdaptor = MorphoAaveV3DebtTokenAdaptor(
            deployer.deployContract("Morpho Aave V3 debtToken Adaptor V 1.2", creationCode, constructorArgs, 0)
        );

        // TODO confirm the identifier is unique in the registry.

        if (registry.isIdentifierUsed(aaveATokenAdaptor.identifier())) revert("Identifier used. 0");
        if (registry.isIdentifierUsed(aaveDebtTokenAdaptor.identifier())) revert("Identifier used. 1");
        if (registry.isIdentifierUsed(aaveV3ATokenAdaptor.identifier())) revert("Identifier used. 2");
        if (registry.isIdentifierUsed(aaveV3DebtTokenAdaptor.identifier())) revert("Identifier used. 3");
        if (registry.isIdentifierUsed(morphoAaveV2ATokenAdaptor.identifier())) revert("Identifier used. 4");
        if (registry.isIdentifierUsed(morphoAaveV2DebtTokenAdaptor.identifier())) revert("Identifier used. 5");
        if (registry.isIdentifierUsed(morphoAaveV3ATokenCollateralAdaptor.identifier())) revert("Identifier used. 6");
        if (registry.isIdentifierUsed(morphoAaveV3DebtTokenAdaptor.identifier())) revert("Identifier used. 7");

        vm.stopBroadcast();
    }
}
