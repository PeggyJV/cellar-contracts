// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry } from "src/base/Cellar.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/DeployV2Script.s.sol:DeployV2Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployV2Script is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private deployer = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    CellarInitializableV2_1 private cellar;

    CellarFactory private factory = CellarFactory(0x95f0eD6581AdF2ee1149fc7830594C7933C876AE);
    Registry private registry = Registry(0xeFFe069b1c62c2f55F41A501eCc3c6Ff4dB6D70a);

    function run() external {
        vm.startBroadcast();

        // Deploy cellar using factory.
        address implementation = address(new CellarInitializableV2_1(registry));

        // factory.addImplementation(implementation, 2, 1);

        vm.stopBroadcast();
    }
}
