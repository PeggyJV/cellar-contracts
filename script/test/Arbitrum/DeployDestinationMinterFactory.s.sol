// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { DestinationMinterFactory } from "src/modules/multi-chain-share/DestinationMinterFactory.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Arbitrum/DeployDestinationMinterFactory.s.sol:DeployDestinationMinterFactoryScript --rpc-url $SEPOLIA_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 2500000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployDestinationMinterFactoryScript is Script {
    address public owner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf;
    uint64 public sourceChainSelector = 6101244977088475029;
    uint64 public destinationChainSelector = 16015286601757825753;
    address public LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address public sourceLockerFactory = 0xe78D206DE3ef350FC66c0933c6c0B5fD16029D49;

    function run() external {
        vm.startBroadcast();
        DestinationMinterFactory minterFactory = new DestinationMinterFactory(
            owner,
            router,
            sourceLockerFactory,
            sourceChainSelector,
            destinationChainSelector,
            LINK
        );
        ERC20(LINK).transfer(address(minterFactory), 10e18);
        vm.stopBroadcast();
    }
}
