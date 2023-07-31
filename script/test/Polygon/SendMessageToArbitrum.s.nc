// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "src/base/Cellar.sol";
import { AxelarProxy } from "src/AxelarProxy.sol";
import { MockSommelier } from "src/mocks/MockSommelier.sol";

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
    string private destAddress = "0x2aF45D06C3d06af1E6B8Bc3f90c5a8DB0E5aa729";

    address private usdcOnArb = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    MockSommelier private mockSomm;

    function run() external {
        vm.startBroadcast();

        mockSomm = new MockSommelier();

        mockSomm.sendMessage{ value: 10 ether }(destAddress, usdcOnArb, devOwner, 777);

        vm.stopBroadcast();
    }
}
