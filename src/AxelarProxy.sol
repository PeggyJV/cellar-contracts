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
     */
    function _execute(string calldata sourceChain, string calldata sender, bytes calldata payload) internal override {
        // Validate Source Chain
        if (keccak256(bytes(sourceChain)) != SOMMELIER_CHAIN_HASH) revert AxelarProxy__WrongSource();
        if (keccak256(bytes(sender)) != SENDER_HASH) revert AxelarProxy__WrongSender();

        (uint8 msgId, address target, uint256 nonce, bytes memory callData, address[] memory targets, uint256[] memory nonces, address newAxelarProxy) = abi
            .decode(payload, (uint8, address, uint256, bytes, address[], uint256[], address)); // TODO: confirm that this is the decoded data we want to move forward with now.

        // Execute function call.

        if ((msgId != logicCallMsgId) || (msgId != upgradeMsgId)) revert AxelarProxy__WrongMsgId();
        if (nonce <= lastRecordedNonce[target]) revert AxelarProxy__NonceTooOld();

        if (msgId == upgradeMsgId) {
            
            if ((targets.length != nonces.length)) revert AxelarProxy__UpgradeArrayLengthMismatch();

            for (uint256 i = 0; i < targets.length; i++) {
                target = targets[i];
                lastRecordedNonce[target] = nonce; // TODO: possibly don't need this.
                IOwned(target).transferOwnership(newAxelarProxy); // owner transference emits events to track.
                // TODO: do we have the callData decoded to check the details of it, or do we have an interface, or do we just trust it? I lean towards having an interface (see the top of this file). 

                // TODO: ALT route we likely have to do if we have to use: `target.callContract()` involves decoding the callData to confirm that the calldata corresponds to a function call to transfer the owner of the target to the newAxelarProxy.
            }
        } else {

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
