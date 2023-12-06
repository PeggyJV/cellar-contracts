// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

abstract contract SafeCCIPReceiver is CCIPReceiver {
    mapping(bytes32 => bool) public messageHashToCanRetry;

    error SafeCCIPReceiver___OnlySelf();
    error SafeCCIPReceiver___BadMessageSender();
    error SafeCCIPReceiver___BadMessageSourceChain();
    error SafeCCIPReceiver___InvalidMessageId();
    error SafeCCIPReceiver___ProvidedGasBufferTooSmall();
    error SafeCCIPReceiver___CanNotRetryMessage();

    /**
     * @notice Estimated gas required for a noOp TX to still be safely handled if reverted.
     * @dev Does not account for gas overhead in `ccipReceive`, but that should be less than 100 gas
     */
    uint128 public gasUsedForNoOp;

    uint128 public gasBuffer;

    modifier onlySelf() {
        if (msg.sender != address(this)) revert SafeCCIPReceiver___OnlySelf();
        _;
    }

    event MessageRevert(bytes32 messageId);
    event MessageSuccess(bytes32 messageId);

    constructor(address _router) CCIPReceiver(_router) {}

    function initialize(uint128 _gasBuffer) external {
        if (gasUsedForNoOp != 0) revert("Already set");

        gasBuffer = _gasBuffer;
        // Create an empty message.
        Client.Any2EVMMessage memory any2EvmMessage;

        // Call _ccipReceive.
        uint256 startingGas = gasleft();
        _ccipReceive(any2EvmMessage);
        gasUsedForNoOp = uint128(startingGas - gasleft());
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        uint128 _gasUsedForNoOp = gasUsedForNoOp;
        uint128 _gasBuffer = gasBuffer;
        uint256 gasToForward = _gasUsedForNoOp == 0 ? _gasBuffer : gasleft() - _gasUsedForNoOp;
        try this.processMessage{ gas: gasToForward }(any2EvmMessage) {} catch (bytes memory lowLevelData) {
            if (_gasUsedForNoOp == 0) {
                // We are currently calling `intialize`.
                if (lowLevelData.length == 0) {
                    // can maybe do a more specific check that we did actually get said error.
                    // We reverted from some error other than `SafeCCIPReceiver___InvalidMessageId` so provided gasBuffer was too small.
                    revert SafeCCIPReceiver___ProvidedGasBufferTooSmall();
                }
            }
            // If any errors ocurred, save message for retry.
            bytes32 messageHash = keccak256(
                abi.encode(
                    any2EvmMessage.messageId,
                    any2EvmMessage.sourceChainSelector,
                    any2EvmMessage.sender,
                    any2EvmMessage.data
                )
            );
            messageHashToCanRetry[messageHash] = true;
            emit MessageRevert(any2EvmMessage.messageId);
        }
    }

    function processMessage(Client.Any2EVMMessage memory any2EvmMessage) public onlySelf {
        if (any2EvmMessage.messageId == bytes32(0)) revert SafeCCIPReceiver___InvalidMessageId(); // This check causes the initialize _ccipReceive call to revert, as long as gasBuffer is large enough
        if (!_isSenderOk(any2EvmMessage.sender)) revert SafeCCIPReceiver___BadMessageSender();
        if (!_isSourceChainOk(any2EvmMessage.sourceChainSelector)) revert SafeCCIPReceiver___BadMessageSourceChain();

        _processMessage(any2EvmMessage);

        emit MessageSuccess(any2EvmMessage.messageId);
    }

    function retryFailedMessage(Client.Any2EVMMessage memory any2EvmMessage) external {
        bytes32 messageHash = keccak256(
            abi.encode(
                any2EvmMessage.messageId,
                any2EvmMessage.sourceChainSelector,
                any2EvmMessage.sender,
                any2EvmMessage.data
            )
        );

        if (!messageHashToCanRetry[messageHash]) revert SafeCCIPReceiver___CanNotRetryMessage();

        messageHashToCanRetry[messageHash] = false;

        this.processMessage(any2EvmMessage);
    }

    /**
     * @notice
     * @dev Math behind calculation.
     *      1x gasBuffer was gas used to call this.processMessage, run `onlySelf` check, and fail from `SafeCCIPReceiver___InvalidMessageId`.
     *      1x gasBuffer because logic in `ccipReceive` uses roughly the same gas as above logic.
     *         - call this.ccipReceive, and run `onlyRouter` check.
     *      1x gasBuffer to add an extra layer of safety from changing opcode costs.
     *      gasUsedForNoOp is the gas required to safely save required data so message can be retried.
     */
    function getMinimumGasToInsureSafeFailure() external view returns (uint256) {
        uint128 _gasUsedForNoOp = gasUsedForNoOp;
        uint128 _gasBuffer = gasBuffer;
        return (3 * _gasBuffer) + _gasUsedForNoOp;
    }

    function _processMessage(Client.Any2EVMMessage memory any2EvmMessage) internal virtual;

    function _isSenderOk(bytes memory sender) internal view virtual returns (bool);

    function _isSourceChainOk(uint64 sourceChainSelector) internal view virtual returns (bool);
}
