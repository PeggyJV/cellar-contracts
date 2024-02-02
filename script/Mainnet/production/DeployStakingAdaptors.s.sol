// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { EtherFiStakingAdaptor } from "src/modules/adaptors/Staking/EtherFiStakingAdaptor.sol";
import { LidoStakingAdaptor } from "src/modules/adaptors/Staking/LidoStakingAdaptor.sol";
import { ERC4626Adaptor } from "src/modules/adaptors/ERC4626Adaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/DeployStakingAdaptors.s.sol:DeployStakingAdaptorsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 */
contract DeployStakingAdaptorsScript is Script, MainnetAddresses {
    using Math for uint256;

    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;
        vm.startBroadcast();

        creationCode = type(EtherFiStakingAdaptor).creationCode;
        constructorArgs = abi.encode(WETH, 16, liquidityPool, withdrawalRequestNft, WEETH, EETH);
        deployer.deployContract("EtherFi Staking Adaptor V0.0", creationCode, constructorArgs, 0);

        creationCode = type(LidoStakingAdaptor).creationCode;
        constructorArgs = abi.encode(WETH, 8, STETH, WSTETH, unstETH);
        deployer.deployContract("Lido Staking Adaptor V0.0", creationCode, constructorArgs, 0);

        // Deploy an ERC4626 Adaptor.
        creationCode = type(ERC4626Adaptor).creationCode;
        constructorArgs = hex"";
        deployer.deployContract("ERC4626 Adaptor V0.0", creationCode, constructorArgs, 0);

        // some CRV vesting conmtract

        vm.stopBroadcast();
    }
}
