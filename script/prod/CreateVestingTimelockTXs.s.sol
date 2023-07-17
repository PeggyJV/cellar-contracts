// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/CreateVestingTimelockTXs.s.sol:CreateVestingTimelockTXsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract CreateVestingTimelockTXsScript is Script {
    TimelockController private controller = TimelockController(payable(0xAa71f75fb6948a6c814A28675241FC5E3bCaC355));
    address private somm = 0xa670d7237398238DE01267472C6f13e5B8010FD1;
    address private dest = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;

    TimelockController private timelock;

    function run() external {
        bytes memory payload0 = abi.encodeWithSelector(ERC20.transfer.selector, dest, 400_000e6);
        bytes memory payload1 = abi.encodeWithSelector(TimelockController.updateDelay.selector, 300);

        vm.startBroadcast();

        controller.schedule(somm, 0, payload0, hex"", hex"", 2 * 365 days);
        controller.schedule(address(controller), 0, payload1, hex"", hex"", 2 * 365 days);

        vm.stopBroadcast();
    }
}
