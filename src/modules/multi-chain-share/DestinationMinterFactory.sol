// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { DestinationMinter } from "./DestinationMinter.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title DestinationMinterFactory
 * @notice Works with SourceLockerFactory to create pairs of Source Lockers & Destination Minters for new bridgeable ERC4626 Shares
 * @dev Source Lockers lock up shares to bridge a mint request to paired Destination Minters, where the representation of the Source Network Shares is minted on Destination Network.
 * @author crispymangoes
 */
contract DestinationMinterFactory is Owned, CCIPReceiver {
    using SafeTransferLib for ERC20;

    // ========================================= GLOBAL STATE =========================================
    /**
     * @notice Mapping to keep track of failed CCIP messages, and retry them at a later time.
     */
    mapping(bytes32 => bool) public canRetryFailedMessage;

    /**
     * @notice The message gas limit to use for CCIP messages.
     */
    uint256 public messageGasLimit;

    /**
     * @notice The message gas limit DestinationMinter's will use to send messages to their SourceLockers.
     */
    uint256 public minterMessageGasLimit;

    //============================== ERRORS ===============================

    error DestinationMinterFactory___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error DestinationMinterFactory___SenderNotAllowlisted(address sender);
    error DestinationMinterFactory___NotEnoughLink();
    error DestinationMinterFactory___CanNotRetryCallback();

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

    constructor(
        address _owner,
        address _router,
        address _sourceLockerFactory,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link,
        uint256 _messageGasLimit,
        uint256 _minterMessageGasLimit
    ) Owned(_owner) CCIPReceiver(_router) {
        sourceLockerFactory = _sourceLockerFactory;
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
        messageGasLimit = _messageGasLimit;
        minterMessageGasLimit = _minterMessageGasLimit;
    }

    //============================== ADMIN FUNCTIONS ===============================

    /**
     * @notice Allows admin to withdraw ERC20s from this factory contract.
     * @param token specified ERC20 to withdraw.
     * @param amount number of ERC20 token to withdraw.
     * @param to receiver of the respective ERC20 tokens.
     */
    function adminWithdraw(ERC20 token, uint256 amount, address to) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    /**
     * @notice Allows admin to set this factories callback CCIP message gas limit.
     * @dev Note Owner can set a gas limit that is too low, and cause the callback messages to run out of gas.
     *           If this happens the owner should raise gas limit, and call `deploy` on SourceLockerFactory again.
     * @param limit Specified CCIP message gas limit.
     */
    function setMessageGasLimit(uint256 limit) external onlyOwner {
        messageGasLimit = limit;
    }

    /**
     * @notice Allows admin to set newly deployed DestinationMinter message gas limits
     * @dev Note This only effects newly deployed DestinationMinters.
     * @param limit Specified CCIP message gas limit.
     */
    function setMinterMessageGasLimit(uint256 limit) external onlyOwner {
        minterMessageGasLimit = limit;
    }

    //============================== RETRY FUNCTIONS ===============================

    /**
     * @notice Allows anyone to retry sending callback to source locker factory.
     * @param targetSource The Source Locker (on source network).
     * @param targetMinter The Destination Minter (on this Destination Network).
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
     * @notice Implement internal _ccipReceive function logic.
     * @param any2EvmMessage CCIP encoded message specifying details to use to create paired DestinationMinter.
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
                address(LINK),
                minterMessageGasLimit
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
     * @param targetSource The Source Locker (on source network).
     * @param targetMinter The Destination Minter (on this Destination Network).
     * @return message the CCIP message to send to source locker factory.
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
                Client.EVMExtraArgsV1({ gasLimit: messageGasLimit /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });
    }
}
