// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "src/base/Cellar.sol";
import { IAxelarGateway } from "lib/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { IAxelarGasService } from "lib/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";

/**
 * @notice This mock contract provides a method to send an Axelar message from one chain to another.
 *         It is called MockSommelier because it is mimicking what the Sommelier chain would do
 *         to send an Axelar message.
 * @dev NOTE for actual Axelar messages from Sommelier, the Cosmos to EVM messaging logic will be used, not EVM to EVM.
 */
contract MockSommelier {
    using Address for address;

    address constant ARB_USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    IAxelarGateway private axelarGateway = IAxelarGateway(0x6f015F16De9fC8791b234eF68D486d2bF203FBA8);
    IAxelarGasService private axelarGasService = IAxelarGasService(0x2d5d7d31F671F86C782533cc367F14109a082712);
    string private destChain = "arbitrum";

    function sendMessage(string memory target, address token, address spender, uint256 amount) external payable {
        bytes memory payload = abi.encodeWithSelector(ERC20.approve.selector, spender, amount);
        payload = abi.encode(token, payload);

        // Pay gas.
        axelarGasService.payNativeGasForContractCall{ value: msg.value }(
            msg.sender,
            destChain,
            target,
            payload,
            msg.sender
        );
        // Send GMP.
        axelarGateway.callContract(destChain, target, payload);
    }
}
