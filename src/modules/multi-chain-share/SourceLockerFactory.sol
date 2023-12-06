// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { SourceLocker } from "./SourceLocker.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

// TODO should we add a mapping from share to locker, and enforce shares are unique?
contract SourceLockerFactory is Owned, CCIPReceiver {
    using SafeTransferLib for ERC20;

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Destination Minter Factory.
     */
    address public destinationMinterFactory;

    //============================== ERRORS ===============================

    error SourceLockerFactory___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SourceLockerFactory___SenderNotAllowlisted(address sender);
    error SourceLockerFactory___NotEnoughLink(); // TODO check for revert

    uint64 public immutable sourceChainSelector;
    uint64 public immutable destinationChainSelector;
    ERC20 public immutable LINK;

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != destinationChainSelector)
            revert SourceLockerFactory___SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != destinationMinterFactory) revert SourceLockerFactory___SenderNotAllowlisted(_sender);
        _;
    }

    function setDestinationMinterFactory(address _destinationMinterFactory) external onlyOwner {
        if (destinationMinterFactory != address(0)) revert("Factory already set");
        destinationMinterFactory = _destinationMinterFactory;
    }

    // TODO add in value so we can set the message gas limit as an immutable
    constructor(
        address _owner,
        address _router,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link
    ) Owned(_owner) CCIPReceiver(_router) {
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
    }

    function deploy(ERC20 target) external onlyOwner returns (bytes32 messageId, address newLocker) {
        // Deploy a new Source Target
        SourceLocker locker = new SourceLocker(
            this.getRouter(),
            address(target),
            address(this),
            sourceChainSelector,
            destinationChainSelector,
            address(LINK)
        );
        // CCIP Send new Source Target address, target.name(), target.symbol(), target.decimals() to DestinationMinterFactory.
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationMinterFactory),
            data: abi.encode(address(locker), target.name(), target.symbol(), target.decimals()),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 2_000_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(destinationChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) revert SourceLockerFactory___NotEnoughLink();

        LINK.safeApprove(address(router), fees);

        messageId = router.ccipSend(destinationChainSelector, message);
        newLocker = address(locker);
    }

    // CCIP Receive function will accept new DestinationMinter address, and corresponding source locker, and call SourceLocker:setTargetDestination()
    // TODO we could add in a mapping assignment here so that people can map the Cellar share to the source locker? It would be possible for the owner to accidentally send 2 deploys back 2 back though
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
    }

    function adminWithdraw(ERC20 token, uint256 amount, address to) external onlyOwner {
        token.safeTransfer(to, amount);
    }
}
