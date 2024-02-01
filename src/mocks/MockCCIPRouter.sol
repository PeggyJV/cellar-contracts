// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract MockCCIPRouter {
    ERC20 public immutable LINK;

    constructor(address _link) {
        LINK = ERC20(_link);
    }

    uint256 public messageCount;

    uint256 public currentFee = 1e18;

    uint64 public constant SOURCE_SELECTOR = 6101244977088475029;
    uint64 public constant DESTINATION_SELECTOR = 16015286601757825753;

    mapping(bytes32 => Client.Any2EVMMessage) public messages;

    bytes32 public lastMessageId;

    function setFee(uint256 newFee) external {
        currentFee = newFee;
    }

    function getLastMessage() external view returns (Client.Any2EVMMessage memory) {
        return messages[lastMessageId];
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return currentFee;
    }

    function ccipSend(uint64 chainSelector, Client.EVM2AnyMessage memory message) external returns (bytes32 messageId) {
        LINK.transferFrom(msg.sender, address(this), currentFee);
        messageId = bytes32(messageCount);
        messageCount++;
        lastMessageId = messageId;
        messages[messageId].messageId = messageId;
        messages[messageId].sourceChainSelector = chainSelector == SOURCE_SELECTOR
            ? DESTINATION_SELECTOR
            : SOURCE_SELECTOR;
        messages[messageId].sender = abi.encode(msg.sender);
        messages[messageId].data = message.data;
    }
}
