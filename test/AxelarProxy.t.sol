// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { AxelarProxy } from "src/AxelarProxy.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// solhint-disable-next-line max-states-count
contract AxelarProxyTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    AxelarProxy public proxy;

    address axelarGateway = 0x4F4495243837681061C4743b74B3eEdf548D56A5;

    function setUp() public {
        proxy = new AxelarProxy(axelarGateway, address(this));
    }

    function testToggle() external {
        proxy.toggleExecution();
        assertTrue(proxy.stopExecute());

        proxy.toggleExecution();
        assertFalse(proxy.stopExecute());

        proxy.toggleExecution();
        assertTrue(proxy.stopExecute());

        proxy.toggleExecution();
        assertFalse(proxy.stopExecute());
    }
}
