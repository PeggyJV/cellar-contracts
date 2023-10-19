// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { SourceLockerFactory } from "src/modules/multi-chain-share/SourceLockerFactory.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Arbitrum/DeploySourceLockerFactory.s.sol:DeploySourceLockerFactoryScript --rpc-url $FUJI_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $SNOWTRACE_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeploySourceLockerFactoryScript is Script {
    address public owner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public router = 0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8;
    uint64 public sourceChainSelector = 14767482510784806043;
    uint64 public destinationChainSelector = 16015286601757825753;
    address public LINK = 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;

    function run() external {
        vm.startBroadcast();
        SourceLockerFactory lockerFactory = new SourceLockerFactory(
            owner,
            router,
            sourceChainSelector,
            destinationChainSelector,
            LINK
        );
        ERC20(LINK).transfer(address(lockerFactory), 10e18);

        MockERC20 erc20 = new MockERC20("GOLD", "GD", 18);

        // lockerFactory.deploy(erc20);

        vm.stopBroadcast();
    }
}
