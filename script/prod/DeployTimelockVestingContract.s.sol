// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "src/base/Cellar.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployTimelockVestingContract.s.sol:DeployTimelockScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTimelockScript is Script {
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private sevenSeas = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    ERC20 private somm = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1);

    TimelockController private timelock;

    function run() external {
        uint256 minDelay = 2 * 365 days;
        address[] memory proposers = new address[](1);
        proposers[0] = devOwner;
        address[] memory executors = new address[](1);
        executors[0] = sevenSeas;
        address admin = sevenSeas;

        vm.startBroadcast();

        timelock = new TimelockController(minDelay, proposers, executors, admin);

        vm.stopBroadcast();
    }
}
