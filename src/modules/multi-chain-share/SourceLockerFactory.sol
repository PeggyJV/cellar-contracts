// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { SourceLocker } from "./SourceLocker.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title SourceLockerFactory
 * @notice Works with DestinationMinterFactory to create pairs of Source Lockers & Destination Minters for new bridgeable ERC4626 Shares
 * @dev SourceLockerFactory `deploy()` function is used to enact the creation of SourceLocker and DestinationMinter pairs.
 * @dev Source Lockers lock up shares to bridge a mint request to paired Destination Minters, where the representation of the Source Network Shares is minted on Destination Network.
 * @author crispymangoes
 */
contract SourceLockerFactory is Owned, CCIPReceiver {
    using SafeTransferLib for ERC20;

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Destination Minter Factory.
     */
    address public destinationMinterFactory;

    /**
     * @notice The message gas limit to use for CCIP messages.
     */
    uint256 public messageGasLimit;

    /**
     * @notice The message gas limit SourceLockers's will use to send messages to their DestinationMinters.
     */
    uint256 public lockerMessageGasLimit;

    //============================== ERRORS ===============================

    error SourceLockerFactory___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SourceLockerFactory___SenderNotAllowlisted(address sender);
    error SourceLockerFactory___NotEnoughLink();
    error SourceLockerFactory___FactoryAlreadySet();

    //============================== EVENTS ===============================

    event DeploySuccess(address share, address locker, address minter);
    event DeploymentInProgress(address share, address locker, bytes32 messageId);

    //============================== MODIFIERS ===============================

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != destinationChainSelector)
            revert SourceLockerFactory___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != destinationMinterFactory) revert SourceLockerFactory___SenderNotAllowlisted(_sender);
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice The CCIP source chain selector.
     */
    uint64 public immutable sourceChainSelector;

    /**
     * @notice The CCIP destination chain selector.
     */
    uint64 public immutable destinationChainSelector;

    /**
     * @notice This network's LINK contract.
     */
    ERC20 public immutable LINK;

    constructor(
        address _owner,
        address _router,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link,
        uint256 _messageGasLimit,
        uint256 _lockerMessageGasLimit
    ) Owned(_owner) CCIPReceiver(_router) {
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
        messageGasLimit = _messageGasLimit;
        lockerMessageGasLimit = _lockerMessageGasLimit;
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
     * @notice Allows admin to link DestinationMinterFactory to this factory.
     * @param _destinationMinterFactory The specified DestinationMinterFactory to pair with this SourceLockerFactory.
     */
    function setDestinationMinterFactory(address _destinationMinterFactory) external onlyOwner {
        if (destinationMinterFactory != address(0)) revert SourceLockerFactory___FactoryAlreadySet();
        destinationMinterFactory = _destinationMinterFactory;
    }

    /**
     * @notice Allows admin to set this factories CCIP message gas limit.
     * @dev Note Owner can set a gas limit that is too low, and cause the message to run out of gas.
     *           If this happens the owner should raise gas limit, and call `deploy` on SourceLockerFactory again.
     * @param limit Specified CCIP message gas limit.
     */
    function setMessageGasLimit(uint256 limit) external onlyOwner {
        messageGasLimit = limit;
    }

    /**
     * @notice Allows admin to set newly deployed SourceLocker message gas limits
     * @dev Note This only effects newly deployed SourceLockers.
     * @param limit Specified CCIP message gas limit.
     */
    function setLockerMessageGasLimit(uint256 limit) external onlyOwner {
        lockerMessageGasLimit = limit;
    }

    /**
     * @notice Allows admin to deploy a new SourceLocker and DestinationMinter, for a given `share`.
     * @dev Note Owner can set a gas limit that is too low, and cause the message to run out of gas.
     *           If this happens the owner should raise gas limit, and call `deploy` on SourceLockerFactory again.
     * @param target Specified `share` token for a ERC4626 vault.
     * @return messageId Resultant CCIP messageId.
     * @return newLocker Newly deployed Source Locker for specified `target`
     */
    function deploy(ERC20 target) external onlyOwner returns (bytes32 messageId, address newLocker) {
        // Deploy a new Source Target
        SourceLocker locker = new SourceLocker(
            this.getRouter(),
            address(target),
            address(this),
            destinationChainSelector,
            address(LINK),
            lockerMessageGasLimit
        );
        // CCIP Send new Source Target address, target.name(), target.symbol(), target.decimals() to DestinationMinterFactory.
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationMinterFactory),
            data: abi.encode(address(locker), target.name(), target.symbol(), target.decimals()),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: messageGasLimit /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(destinationChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) revert SourceLockerFactory___NotEnoughLink();

        LINK.safeApprove(address(router), fees);

        messageId = router.ccipSend(destinationChainSelector, message);
        newLocker = address(locker);

        emit DeploymentInProgress(address(target), newLocker, messageId);
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipReceive function logic.
     * @param any2EvmMessage CCIP encoded message specifying details to use to `setTargetDestination()` && finish creating pair of Source Locker & Destination Minter for specified `share`.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (address targetLocker, address targetDestination) = abi.decode(any2EvmMessage.data, (address, address));

        SourceLocker locker = SourceLocker(targetLocker);

        locker.setTargetDestination(targetDestination);

        emit DeploySuccess(address(locker.shareToken()), targetLocker, targetDestination);
    }
}
