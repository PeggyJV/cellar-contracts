// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/DeployAaveDebtTokenAdaptor.s.sol:DeployAaveDebtTokenAdaptor --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAaveDebtTokenAdaptor is Script {
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;

    function run() external {
        vm.startBroadcast();

        // Deploy UniswapV3 Adaptor.
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor();

        vm.stopBroadcast();
    }
}
