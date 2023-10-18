// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";
import { Math } from "src/utils/Math.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract DestinationMinter is ERC20, CCIPReceiver {
    using SafeTransferLib for ERC20;
    address public immutable targetSource;
    uint64 public immutable sourceChainSelector;
    uint64 public immutable destinationChainSelector;
    ERC20 public immutable LINK;

    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector) revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != targetSource) revert SenderNotAllowlisted(_sender);
        _;
    }

    constructor(
        address _router,
        address _targetSource,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link
    ) ERC20(_name, _symbol, _decimals) CCIPReceiver(_router) {
        targetSource = _targetSource;
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
    }

    // CCIP Receive, sender must be targetSource
    // mint shares to some address
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        (uint256 amount, address to) = abi.decode(any2EvmMessage.data, (uint256, address));
        _mint(to, amount);
    }

    // On token burn, send CCIP message to targetSource with amount, and to address
    function bridgeToSource(uint256 amount, address to, uint256 maxLinkToPay) external returns (bytes32 messageId) {
        if (to == address(0)) revert("Invalid to");
        _burn(msg.sender, amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(targetSource),
            data: abi.encode(amount, to),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(sourceChainSelector, message);

        if (fees > maxLinkToPay) revert("Not enough link");

        LINK.safeTransferFrom(msg.sender, address(this), fees);

        LINK.approve(address(router), fees);

        messageId = router.ccipSend(sourceChainSelector, message);
    }
}
