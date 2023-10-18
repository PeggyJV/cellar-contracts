// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { SourceLocker } from "./SourceLocker.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract SourceLockerFactory is Owned, CCIPReceiver {
    address public destinationMinterFactory;
    uint64 public immutable sourceChainSelector;
    uint64 public immutable destinationChainSelector;
    ERC20 public immutable LINK;

    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != destinationChainSelector) revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != destinationMinterFactory) revert SenderNotAllowlisted(_sender);
        _;
    }

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

    function deploy(ERC4626 target) external onlyOwner returns (bytes32 messageId) {
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
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(destinationChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) revert("Not enough link");

        LINK.approve(address(router), fees);

        messageId = router.ccipSend(destinationChainSelector, message);
    }

    // CCIP Receive function will accept new DestinationMinter address, and corresponding source locker, and call SourceLocker:setTargetDestination()
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

    // TODO function to withdraw ERC20s from this, so owner can withdraw LINK.
}
