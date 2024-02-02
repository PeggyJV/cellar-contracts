// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * @title DestinationMinter
 * @notice Receives CCIP messages from SourceLocker, to mint ERC20 shares that
 *         represent ERC4626 shares locked on source chain.
 * @author crispymangoes
 */
contract DestinationMinter is ERC20, CCIPReceiver {
    using SafeTransferLib for ERC20;

    //============================== ERRORS ===============================

    error DestinationMinter___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error DestinationMinter___SenderNotAllowlisted(address sender);
    error DestinationMinter___InvalidTo();
    error DestinationMinter___FeeTooHigh();

    //============================== EVENTS ===============================

    event BridgeToSource(uint256 amount, address to, bytes32 messageId);
    event BridgeFromSource(uint256 amount, address to);

    //============================== MODIFIERS ===============================

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector)
            revert DestinationMinter___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != targetSource) revert DestinationMinter___SenderNotAllowlisted(_sender);
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice The address of the SourceLocker on source chain.
     */
    address public immutable targetSource;

    /**
     * @notice The CCIP source chain selector.
     */
    uint64 public immutable sourceChainSelector;

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
        address _targetSource,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _sourceChainSelector,
        address _link,
        uint256 _messageGasLimit
    ) ERC20(_name, _symbol, _decimals) CCIPReceiver(_router) {
        targetSource = _targetSource;
        sourceChainSelector = _sourceChainSelector;
        LINK = ERC20(_link);
        messageGasLimit = _messageGasLimit;
    }

    //============================== BRIDGE ===============================

    /**
     * @notice Bridge shares back to source chain.
     * @dev Caller should approve LINK to be spent by this contract.
     * @param amount Number of shares to burn on destination network and unlock/transfer on source network.
     * @param to The address to send unlocked share tokens to on the source chain.
     * @param maxLinkToPay Specified max amount of LINK fees to pay as per this contract.
     * @return messageId Resultant CCIP messageId.
     */
    function bridgeToSource(uint256 amount, address to, uint256 maxLinkToPay) external returns (bytes32 messageId) {
        if (to == address(0)) revert DestinationMinter___InvalidTo();
        _burn(msg.sender, amount);

        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(sourceChainSelector, message);

        if (fees > maxLinkToPay) revert DestinationMinter___FeeTooHigh();

        LINK.safeTransferFrom(msg.sender, address(this), fees);

        LINK.safeApprove(address(router), fees);

        messageId = router.ccipSend(sourceChainSelector, message);
        emit BridgeToSource(amount, to, messageId);
    }

    //============================== VIEW FUNCTIONS ===============================

    /**
     * @notice Preview fee required to bridge shares back to source.
     * @param amount Specified amount of `share` tokens to bridge to source network.
     * @param to Specified address to receive bridged shares on source network.
     * @return fee required to bridge shares.
     */
    function previewFee(uint256 amount, address to) public view returns (uint256 fee) {
        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        fee = router.getFee(sourceChainSelector, message);
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipRecevie function logic.
     * @param any2EvmMessage CCIP encoded message specifying details to use to 'mint' `share` tokens to a specified address `to` on destination network.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 amount, address to) = abi.decode(any2EvmMessage.data, (uint256, address));
        _mint(to, amount);
        emit BridgeFromSource(amount, to);
    }

    //============================== INTERNAL HELPER ===============================

    /**
     * @notice Build the CCIP message to send to source locker.
     * @param amount number of `share` token to bridge.
     * @param to Specified address to receive unlocked bridged shares on source network.
     * @return message the CCIP message to send to source locker.
     */
    function _buildMessage(uint256 amount, address to) internal view returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(targetSource),
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
