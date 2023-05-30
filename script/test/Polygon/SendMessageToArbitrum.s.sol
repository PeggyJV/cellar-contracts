// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/Cellar.sol";
import { AxelarProxy } from "src/AxelarProxy.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

interface Gateway {
    function callContract(string memory dest, string memory destAddress, bytes memory payload) external;
}

/**
 * @dev Run
 *      `source .env && forge script script/test/Polygon/SendMessageToArbitrum.s.sol:SendMessageToArbitrumScript --rpc-url $MATIC_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --verify --etherscan-api-key $POLYGONSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SendMessageToArbitrumScript is Script {
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Gateway private gateway = Gateway(0x6f015F16De9fC8791b234eF68D486d2bF203FBA8);

    string private destChain = "arbitrum";
    string private destAddress = "0xf399BfA0b50aFb6B2880eCe84671b03c665036AA";

    address private usdcOnArb = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    function run() external {
        vm.startBroadcast();

        bytes memory payload = abi.encodeWithSelector(ERC20.approve.selector, devOwner, 777);
        payload = abi.encode(usdcOnArb, payload);

        gateway.callContract(destChain, destAddress, payload);

        vm.stopBroadcast();
    }
}
