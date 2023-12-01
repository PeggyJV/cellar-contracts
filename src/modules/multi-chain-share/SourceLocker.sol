// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract SourceLocker is CCIPReceiver {
    using SafeTransferLib for ERC20;
    ERC20 public immutable shareToken;
    address public immutable factory;
    address public targetDestination;
    uint64 public immutable sourceChainSelector;
    uint64 public immutable destinationChainSelector;
    ERC20 public immutable LINK;

    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != destinationChainSelector) revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != targetDestination) revert SenderNotAllowlisted(_sender);
        _;
    }

    constructor(
        address _router,
        address _shareToken,
        address _factory,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link
    ) CCIPReceiver(_router) {
        shareToken = ERC20(_shareToken);
        factory = _factory;
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
    }

    function setTargetDestination(address _targetDestination) external {
        if (msg.sender != factory) revert("no no no");
        if (targetDestination != address(0)) revert("target already set");

        targetDestination = _targetDestination;
    }

    // CCIP Receieve sender must be targetDestination
    // transfer shareToken amount and to to
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 amount, address to) = abi.decode(any2EvmMessage.data, (uint256, address));
        shareToken.safeTransfer(to, amount);
    }

    function previewFee(uint256 amount, address to) public view returns (uint256 fee) {
        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        fee = router.getFee(destinationChainSelector, message);
    }

    // on shareToken lock, transfer shareTokens in, and CCIP Send to targetDestination amount and to address
    function bridgeToDestination(
        uint256 amount,
        address to,
        uint256 maxLinkToPay
    ) external returns (bytes32 messageId) {
        if (to == address(0)) revert("Invalid to");
        shareToken.safeTransferFrom(msg.sender, address(this), amount);

        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(destinationChainSelector, message);

        if (fees > maxLinkToPay) revert("Not enough link");

        LINK.safeTransferFrom(msg.sender, address(this), fees);

        LINK.approve(address(router), fees);

        messageId = router.ccipSend(destinationChainSelector, message);
    }

    function _buildMessage(uint256 amount, address to) internal view returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(targetDestination),
            data: abi.encode(amount, to),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });
    }
}
