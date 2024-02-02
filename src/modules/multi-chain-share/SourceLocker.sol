// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * @title SourceLocker
 * @notice Sends and receives CCIP messages to/from DestinationMinter to lock&mint / redeem&release ERC4626 shares from destination chain.
 * @author crispymangoes
 */
contract SourceLocker is CCIPReceiver {
    using SafeTransferLib for ERC20;

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice The Destination Minter on destination chain.
     */
    address public targetDestination;

    //============================== ERRORS ===============================

    error SourceLocker___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SourceLocker___SenderNotAllowlisted(address sender);
    error SourceLocker___OnlyFactory();
    error SourceLocker___TargetDestinationAlreadySet();
    error SourceLocker___InvalidTo();
    error SourceLocker___FeeTooHigh();
    error SourceLocker___TargetDestinationNotSet();

    //============================== EVENTS ===============================

    event BridgeToDestination(uint256 amount, address to, bytes32 messageId);
    event BridgeFromDestination(uint256 amount, address to);

    //============================== MODIFIERS ===============================

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != destinationChainSelector)
            revert SourceLocker___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != targetDestination) revert SourceLocker___SenderNotAllowlisted(_sender);
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice ERC20 share token to bridge.
     */
    ERC20 public immutable shareToken;

    /**
     * @notice The address of the SourceLockerFactory.
     */
    address public immutable factory;

    /**
     * @notice The CCIP destination chain selector.
     */
    uint64 public immutable destinationChainSelector;

    /**
     * @notice This networks LINK contract.
     */
    ERC20 public immutable LINK;

    /**
     * @notice The message gas limit to use for CCIP messages.
     */
    uint256 public immutable messageGasLimit;

    constructor(
        address _router,
        address _shareToken,
        address _factory,
        uint64 _destinationChainSelector,
        address _link,
        uint256 _messageGasLimit
    ) CCIPReceiver(_router) {
        shareToken = ERC20(_shareToken);
        factory = _factory;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
        messageGasLimit = _messageGasLimit;
    }

    //============================== ONLY FACTORY ===============================

    /**
     * @notice Allows factory to set target destination.
     * @param _targetDestination The Destination Minter to pair with this Source Locker.
     */
    function setTargetDestination(address _targetDestination) external {
        if (msg.sender != factory) revert SourceLocker___OnlyFactory();
        if (targetDestination != address(0)) revert SourceLocker___TargetDestinationAlreadySet();

        targetDestination = _targetDestination;
    }

    //============================== BRIDGE ===============================

    /**
     * @notice Bridge shares to destination chain.
     * @notice Reverts if target destination is not yet set.
     * @param amount number of `share` token to bridge.
     * @param to Specified address to receive newly minted bridged shares on destination network.
     * @param maxLinkToPay Specified max amount of LINK fees to pay.
     * @return messageId Resultant CCIP messageId.
     */
    function bridgeToDestination(
        uint256 amount,
        address to,
        uint256 maxLinkToPay
    ) external returns (bytes32 messageId) {
        if (to == address(0)) revert SourceLocker___InvalidTo();
        shareToken.safeTransferFrom(msg.sender, address(this), amount);

        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(destinationChainSelector, message);

        if (fees > maxLinkToPay) revert SourceLocker___FeeTooHigh();

        LINK.safeTransferFrom(msg.sender, address(this), fees);

        LINK.safeApprove(address(router), fees);

        messageId = router.ccipSend(destinationChainSelector, message);
        emit BridgeToDestination(amount, to, messageId);
    }

    //============================== VIEW FUNCTIONS ===============================

    /**
     * @notice Preview fee required to bridge shares to destination.
     * @param amount Specified amount of `share` tokens to bridge to destination network.
     * @param to Specified address to receive newly minted bridged shares on destination network.
     * @return fee required to bridge shares.
     */
    function previewFee(uint256 amount, address to) public view returns (uint256 fee) {
        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        fee = router.getFee(destinationChainSelector, message);
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipReceive function logic.
     * @param any2EvmMessage CCIP encoded message specifying details to use to 'unlock' `share` tokens to transfer to specified address `to`.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 amount, address to) = abi.decode(any2EvmMessage.data, (uint256, address));
        shareToken.safeTransfer(to, amount);
        emit BridgeFromDestination(amount, to);
    }

    //============================== INTERNAL HELPER ===============================

    /**
     * @notice Build the CCIP message to enact minting of bridged `share` tokens via destination minter on destination network.
     * @notice Reverts if target destination is not yet set.
     * @param amount number of `share` token to bridge.
     * @param to Specified address to receive newly minted bridged shares on destination network.
     * @return message the CCIP message to send to destination minter.
     */
    function _buildMessage(uint256 amount, address to) internal view returns (Client.EVM2AnyMessage memory message) {
        address _targetDestination = targetDestination;
        if (_targetDestination == address(0)) revert SourceLocker___TargetDestinationNotSet();
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(_targetDestination),
            data: abi.encode(amount, to),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: messageGasLimit /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });
    }
}
