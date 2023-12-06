// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { DestinationMinter } from "./DestinationMinter.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

// TODO a way to set gas limit for all these contracts sending CCIP messages. Maybe immutable maybe owner?
contract DestinationMinterFactory is Owned, CCIPReceiver {
    using SafeTransferLib for ERC20;

    // ========================================= GLOBAL STATE =========================================

    mapping(bytes32 => bool) public canRetryFailedMessage;

    //============================== ERRORS ===============================

    error DestinationMinterFactory___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error DestinationMinterFactory___SenderNotAllowlisted(address sender);
    error DestinationMinterFactory___NotEnoughLink(); // TODO check for revert
    error DestinationMinterFactory___CanNotRetryCallback(); // TODO check for revert

    //============================== EVENTS ===============================

    event CallBackMessageId(bytes32 id);
    event FailedToSendCallBack(address source, address minter);

    //============================== MODIFIERS ===============================

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector)
            revert DestinationMinterFactory___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != sourceLockerFactory) revert DestinationMinterFactory___SenderNotAllowlisted(_sender);
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice The address of the SourceLockerFactory.
     */
    address public immutable sourceLockerFactory;

    /**
     * @notice The CCIP source chain selector.
     */
    uint64 public immutable sourceChainSelector;

    /**
     * @notice The CCIP destination chain selector.
     */
    uint64 public immutable destinationChainSelector;

    /**
     * @notice This networks LINK contract.
     */
    ERC20 public immutable LINK;

    // TODO add in value so we can set the message gas limit as an immutable
    constructor(
        address _owner,
        address _router,
        address _sourceLockerFactory,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link
    ) Owned(_owner) CCIPReceiver(_router) {
        sourceLockerFactory = _sourceLockerFactory;
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
    }

    //============================== ADMIN FUNCTIONS ===============================

    /**
     * @notice Allows admin to withdraw ERC20s from this factory contract.
     */
    function adminWithdraw(ERC20 token, uint256 amount, address to) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    //============================== RETRY FUNCTIONS ===============================

    // TODO test this functionality.
    /**
     * @notice Allows anyone to retry sending callback to source locker factory.
     */
    function retryCallback(address targetSource, address targetMinter) external {
        bytes32 messageDataHash = keccak256(abi.encode(targetSource, targetMinter));
        if (!canRetryFailedMessage[messageDataHash]) revert DestinationMinterFactory___CanNotRetryCallback();

        canRetryFailedMessage[messageDataHash] = false;

        Client.EVM2AnyMessage memory message = _buildMessage(targetSource, targetMinter);

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(sourceChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) revert DestinationMinterFactory___NotEnoughLink();

        LINK.safeApprove(address(router), fees);

        bytes32 messageId = router.ccipSend(sourceChainSelector, message);
        emit CallBackMessageId(messageId);
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipRecevie function logic.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (address targetSource, string memory name, string memory symbol, uint8 decimals) = abi.decode(
            any2EvmMessage.data,
            (address, string, string, uint8)
        );

        IRouterClient router = IRouterClient(this.getRouter());

        address targetMinter = address(
            new DestinationMinter(
                address(router),
                targetSource,
                name,
                symbol,
                decimals,
                sourceChainSelector,
                destinationChainSelector,
                address(LINK)
            )
        );
        // CCIP sends message back to SourceLockerFactory with new DestinationMinter address, and corresponding source locker
        Client.EVM2AnyMessage memory message = _buildMessage(targetSource, targetMinter);

        uint256 fees = router.getFee(sourceChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) {
            // Fees is larger than the LINK in contract, so update `canRetryFailedMessage`, and return.
            bytes32 messageDataHash = keccak256(abi.encode(targetSource, targetMinter));
            canRetryFailedMessage[messageDataHash] = true;
            emit FailedToSendCallBack(targetSource, targetMinter);
            return;
        }

        LINK.safeApprove(address(router), fees);

        bytes32 messageId = router.ccipSend(sourceChainSelector, message);
        emit CallBackMessageId(messageId);
    }

    //============================== INTERNAL HELPER FUNCTIONS ===============================

    /**
     * @notice Build the CCIP message to send to source locker factory.
     */
    function _buildMessage(
        address targetSource,
        address targetMinter
    ) internal view returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(sourceLockerFactory),
            data: abi.encode(targetSource, targetMinter),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });
    }
}
