// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {AtomicQueue} from "src/modules/atomic-queue/AtomicQueue.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Mainnet/production/DeployAtomicQueue.s.sol:DeployAtomicQueueScript --with-gas-price 60000000000 --slow --broadcast --etherscan-api-key $MAINNET_RPC_URL --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAtomicQueueScript is Script {
    uint256 public privateKey;

    AtomicQueue public queue;

    address public devOwner = 0x2322ba43eFF1542b6A7bAeD35e66099Ea0d12Bd1;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);

        queue = new AtomicQueue();

        vm.stopBroadcast();
    }
}
