// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployTimelock.s.sol:DeployTimelockScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTimelockScript is Script {
    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private otherDevAddress = 0xF3De89fAD937c11e770Bc6291cb5E04d8784aE0C;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    TimelockController private timelock;

    function run() external {
        uint256 minDelay = 3 days;
        address[] memory proposers = new address[](3);
        address[] memory executors = new address[](1);
        address admin = multisig;

        proposers[0] = devOwner;
        proposers[1] = multisig;
        proposers[2] = otherDevAddress;

        executors[0] = multisig;

        vm.startBroadcast();

        timelock = new TimelockController(minDelay, proposers, executors, admin);

        vm.stopBroadcast();
    }
}
