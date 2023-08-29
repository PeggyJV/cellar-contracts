// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AxelarExecutable } from "lib/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @notice Interface to process transferOwnership calls when upgrading to a new AxelarProxyCellar. This transfers ownership of the target chain's cellars specified in the call.
 */
interface IOwned {
    function transferOwnership(address newOwner) external;
}

/**
 * @title Axelar Proxy
 * @notice Allows for Cellars deployed on L2s to be controlled by the Sommelier Chain using Axelar messages.
 * @dev This contract will be deployed on some L2, then to run a Cellar on that L2,
 *      deploy the Cellar, and make this contract the owner.
 * @author crispymangoes, 0xEinCodes
 * NOTE: AxelarProxy accepts different types of msgIds. logicCalls && transferrance of ownership calls. This is where the cellars on a target chain would have to have their owners changed to the new AxelarProxy during an upgrade.
 */
contract AxelarProxy is AxelarExecutable {
    using Address for address;

    event LogicCallEvent(address indexed target, uint256 nonce, bytes callData);

    error AxelarProxy__WrongSource();
    error AxelarProxy__NoTokens();
    error AxelarProxy__WrongSender();
    error AxelarProxy__WrongMsgId();
    error AxelarProxy__NonceTooOld();
    error AxelarProxy__IncorrectUpgradeCallData();
    error AxelarProxy__UpgradeArrayLengthMismatch();

    mapping(address => uint256) public lastRecordedNonce;

    /**
     * @notice Identifier for the expected msg type from the source chain to execute logicCalls on target chains.
     * NOTE: contract calls are the first type, thus starting at 0.
     */
    uint16 public immutable logicCallMsgId = 0;

    /**
     * @notice Identifier for the expeted msg type from the source chain to upgrade ownership of target chain cellars to new AxelarProxy.
     */
    uint16 public immutable upgradeMsgId = 1;

    /**
     * @notice Constant ensuring that the source chain is the anticipated Sommelier chain.
     * NOTE: string literal comes from Axelar.
     */
    bytes32 public constant SOMMELIER_CHAIN_HASH = keccak256(bytes("sommelier"));

    /**
     * @notice Trusted sender hash from Sommelier <> Axelar module.
     */
    bytes32 public immutable SENDER_HASH = keccak256(bytes("___")); // TODO: Get correct string value from protocol team

    /**
     * @param gateway_ address for respective EVM acting as source of truth for approved messaging
     * NOTE: TODO: Possibly add a bound to the nonce.
     */
    constructor(address gateway_) AxelarExecutable(gateway_) {}

    /**
     * @notice Execution logic.
     * @dev Verifies message is from Sommelier, otherwise reverts.
     * @dev Verifies message is a valid Axelar message, otherwise reverts.
     *      See `AxelarExecutable.sol`.
     * TODO: Currently, the problem that we are solving is that we need the msgId from the payload and then we want to have conditional logic branch off to decode the payloads (which differ in structure based on msgId). The issue is that the msgId is part of the payload, so we'd need to decode it. We thought to typecast it thinking that the first word of the bytes array of the payload would be a bytes32, but it is actually a bytes1. Now we are considering other options. One possible solution: import BytesLib, slice the bytes array to get the first two words (recall the first word is the length, so we want the second one). Then we can typecast (decode) that slice to get the msgId.
     * TODO: Either way, we'll need to run tests --> mock contract should be created that takes an encoding, passes it in, and it responds as expected.
     */
    function _execute(string calldata sourceChain, string calldata sender, bytes calldata payload) internal override {
        // Validate Source Chain
        if (keccak256(bytes(sourceChain)) != SOMMELIER_CHAIN_HASH) revert AxelarProxy__WrongSource();
        if (keccak256(bytes(sender)) != SENDER_HASH) revert AxelarProxy__WrongSender();

        uint16 msgId = uint16(uint256(payload[0])); // TODO: This is the first idea but it is coming up with errors when trying to compile.

        if ((msgId != logicCallMsgId) || (msgId != upgradeMsgId)) revert AxelarProxy__WrongMsgId();

        if (msgId == upgradeMsgId) {
            (, address newAxelarProxy, address[] memory targets) = abi.decode(payload, (uint16, address, address[])); // TODO: should we include nonce here (aka is it a requirement or easier with payload data from protocol. As well, do we want to consider a nonce array --> aka if we want to do the similar check with lastRecordedNonce stuff. On the latter, auditor and sc team think no, but good to get protocol team thoughts here.

            for (uint256 i = 0; i < targets.length; i++) {
                address target = targets[i];
                IOwned(target).transferOwnership(newAxelarProxy); // owner transference emits events to track.
            }
        } else {
            (, address target, uint256 nonce, bytes memory callData) = abi.decode(
                payload,
                (uint16, address, uint256, bytes)
            );
            if (nonce <= lastRecordedNonce[target]) revert AxelarProxy__NonceTooOld();
            lastRecordedNonce[target] = nonce;
            target.functionCall(callData);
            emit LogicCallEvent(target, nonce, callData);
        }
    }

    /**
     * @notice This contract is not setup to handle ERC20 tokens, so execution with token calls will revert.
     */
    function _executeWithToken(
        string calldata,
        string calldata,
        bytes calldata,
        string calldata,
        uint256
    ) internal pure override {
        revert AxelarProxy__NoTokens();
    }
}
