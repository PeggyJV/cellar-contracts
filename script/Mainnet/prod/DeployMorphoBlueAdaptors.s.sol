// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { Registry } from "src/Registry.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import "forge-std/Script.sol";

import { MorphoBlueSupplyAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import { MorphoBlueDebtAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueDebtAdaptor.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { MorphoBlueCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueCollateralAdaptor.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/prod/DeployMorphoBlueAdaptors.s.sol:DeployMorphoBlueAdaptorsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMorphoBlueAdaptorsScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x6d3655EE04820f4385a910FD1898d4Ec6241F520;
    Deployer public deployer = Deployer(deployerAddress);

    MorphoBlueCollateralAdaptor public morphoBlueCollateralAdaptor;
    MorphoBlueDebtAdaptor public morphoBlueDebtAdaptor;
    MorphoBlueSupplyAdaptor public morphoBlueSupplyAdaptor;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        uint256 minHealthFactor = 1.05e18;

        vm.startBroadcast();

        // Deploy Morpho Blue Supply Adaptor.
        {
            creationCode = type(MorphoBlueSupplyAdaptor).creationCode;
            constructorArgs = abi.encode(_morphoBlue);
            morphoBlueSupplyAdaptor = MorphoBlueSupplyAdaptor(
                deployer.deployContract("Morpho Blue Supply Adaptor V 0.0", creationCode, constructorArgs, 0)
            );
        }

        // Deploy Morpho Blue Collateral Adaptor.
        {
            creationCode = type(MorphoBlueCollateralAdaptor).creationCode;
            constructorArgs = abi.encode(address(_morphoBlue), minHealthFactor);
            morphoBlueCollateralAdaptor = MorphoBlueCollateralAdaptor(
                deployer.deployContract("Morpho Blue Collateral Adaptor V 0.0", creationCode, constructorArgs, 0)
            );
        }

        // Deploy Morpho Blue Debt Adaptor.
        {
            creationCode = type(MorphoBlueDebtAdaptor).creationCode;
            constructorArgs = abi.encode(address(_morphoBlue), minHealthFactor);
            morphoBlueDebtAdaptor = MorphoBlueDebtAdaptor(
                deployer.deployContract("Morpho Blue Debt Adaptor V 0.0", creationCode, constructorArgs, 0)
            );
        }

        vm.stopBroadcast();
    }
}