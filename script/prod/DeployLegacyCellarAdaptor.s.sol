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

import { LegacyCellarAdaptor } from "src/modules/adaptors/Sommelier/LegacyCellarAdaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployLegacyCellarAdaptor.s.sol:DeployLegacyCellarAdaptorScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployLegacyCellarAdaptorScript is Script, MainnetAddresses {
    using Math for uint256;

    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        vm.startBroadcast();

        bytes memory creationCode;
        bytes memory constructorArgs;

        creationCode = type(LegacyCellarAdaptor).creationCode;
        constructorArgs = hex"";
        deployer.deployContract("Legacy Cellar Adaptor V0.0", creationCode, constructorArgs, 0);

        vm.stopBroadcast();
    }
}
