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

contract DestinationMinterFactory is Owned, CCIPReceiver {
    using SafeTransferLib for ERC20;

    address public immutable sourceLockerFactory;
    uint64 public immutable sourceChainSelector;
    uint64 public immutable destinationChainSelector;
    ERC20 public immutable LINK;

    event CallBackMessageId(bytes32 id);

    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (_sourceChainSelector != sourceChainSelector) revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (_sender != sourceLockerFactory) revert SenderNotAllowlisted(_sender);
        _;
    }

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

    // CCIP Recieve accepts message from SourceLockerFactory with following values.
    //new Source Target address, target.name(), target.symbol(), target.decimals()
    // Deploys a new Destination Minter
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
        DestinationMinter minter = new DestinationMinter(
            this.getRouter(),
            targetSource,
            name,
            symbol,
            decimals,
            sourceChainSelector,
            destinationChainSelector,
            address(LINK)
        );
        // CCIP sends message back to SourceLockerFactory with new DestinationMinter address, and corresponding source locker
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sourceLockerFactory),
            data: abi.encode(targetSource, address(minter)),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(LINK)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(sourceChainSelector, message);

        if (fees > LINK.balanceOf(address(this))) revert("Not enough link");

        LINK.approve(address(router), fees);

        bytes32 messageId = router.ccipSend(sourceChainSelector, message);
        emit CallBackMessageId(messageId);
    }

    function adminWithdraw(ERC20 token, uint256 amount, address to) external onlyOwner {
        token.safeTransfer(to, amount);
    }
}
