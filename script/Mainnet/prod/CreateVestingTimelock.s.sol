// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/CreateVestingTimelock.s.sol:CreateVestingTimelockScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract CreateVestingTimelockScript is Script {
    // TimelockController private controller = TimelockController(payable(0xAa71f75fb6948a6c814A28675241FC5E3bCaC355));
    address private somm = 0xa670d7237398238DE01267472C6f13e5B8010FD1;
    address private dest = 0xF449eeDe7C26A1A051fd9F3A4Dd29eBa42782904;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    TimelockController private timelock;

    function run() external {
        uint256 minDelay = 2 * 365 days;
        address[] memory proposers = new address[](2);
        address[] memory executors = new address[](1);
        address admin = dest;

        proposers[0] = devOwner;
        proposers[1] = dest;

        executors[0] = dest;

        bytes memory payload0 = abi.encodeWithSelector(ERC20.transfer.selector, dest, 400_000e6);
        bytes memory payload1 = abi.encodeWithSelector(TimelockController.updateDelay.selector, 300);

        vm.startBroadcast();
        timelock = new TimelockController(minDelay, proposers, executors, admin);

        timelock.schedule(somm, 0, payload0, hex"", hex"", 2 * 365 days);
        timelock.schedule(address(timelock), 0, payload1, hex"", hex"", 2 * 365 days);

        vm.stopBroadcast();
    }
}
