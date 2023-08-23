// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AxelarExecutable } from "lib/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Axelar Proxy
 * @notice Allows for Cellars deployed on L2s to be controlled by the Sommelier Chain using Axelar messages.
 * @dev This contract will be deployed on some L2, then to run a Cellar on that L2,
 *      deploy the Cellar, and make this contract the owner.
 * @author crispymangoes, 0xEinCodes
 */
contract AxelarProxy is AxelarExecutable {
    using Address for address;

    event LogicCallEvent(address indexed target, uint256 nonce, bytes callData);

    error AxelarProxy__WrongSource();
    error AxelarProxy__NoTokens();
    error AxelarProxy__WrongSender();
    error AxelarProxy__WrongMsgId();
    error AxelarProxy__MinimumNonceUnmet();
    error AxelarProxy__NonceTooOld();

    uint256 public immutable minimumNonce;
    mapping(address => uint256) public lastRecordedNonce;

    /**
     * @notice Identifier for the expected msg type from the source chain.
     * NOTE: contract calls are the first type, thus starting at 0.
     */
    uint16 public immutable logicCallMsgId = 0;

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
     * @param minimumNonce_ where at time of proxy contract deployment, contract calls that are below this nonce value will be invalidated. Upgrading the proxy is the scenario where this is mainly used so as to not allow contract calls created prior to the usage of this new proxy.
     * TODO: adjust any deployment scripts with new minimumNonce_ param
     */
    constructor(address gateway_, uint256 minimumNonce_) AxelarExecutable(gateway_) {
        minimumNonce = minimumNonce_;
    }

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

        (uint8 msgId, address target, uint256 nonce, bytes memory callData) = abi.decode(
            payload,
            (uint8, address, uint256, bytes)
        );

        // Execute function call.

        if (msgId != logicCallMsgId) revert AxelarProxy__WrongMsgId();
        if (nonce < minimumNonce) revert AxelarProxy__MinimumNonceUnmet();
        if (nonce <= lastRecordedNonce[target]) revert AxelarProxy__NonceTooOld();

        lastRecordedNonce[target] = nonce;
        target.functionCall(callData);
        emit LogicCallEvent(target, nonce, callData);
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
