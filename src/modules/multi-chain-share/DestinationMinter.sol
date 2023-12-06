// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { SafeCCIPReceiver } from "src/utils/SafeCCIPReceiver.sol";

contract DestinationMinter is ERC20, SafeCCIPReceiver {
    using SafeTransferLib for ERC20;

    //============================== ERRORS ===============================

    error DestinationMinter___SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error DestinationMinter___SenderNotAllowlisted(address sender);
    error DestinationMinter___InvalidTo();
    error DestinationMinter___FeeTooHigh();

    //============================== EVENTS ===============================

    event BridgeToSource(uint256 amount, address to);
    event BridgeFromSource(uint256 amount, address to);

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
     * @notice The CCIP destination chain selector.
     */
    uint64 public immutable destinationChainSelector;

    /**
     * @notice This networks LINK contract.
     */
    ERC20 public immutable LINK;

    // TODO add in value so we can set the message gas limit as an immutable
    constructor(
        address _router,
        address _targetSource,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint64 _sourceChainSelector,
        uint64 _destinationChainSelector,
        address _link
    ) ERC20(_name, _symbol, _decimals) SafeCCIPReceiver(_router) {
        targetSource = _targetSource;
        sourceChainSelector = _sourceChainSelector;
        destinationChainSelector = _destinationChainSelector;
        LINK = ERC20(_link);
    }

    //============================== BRIDGE ===============================

    /**
     * @notice Bridge shares back to source chain.
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
        emit BridgeToSource(amount, to);
    }

    //============================== VIEW FUNCTIONS ===============================

    /**
     * @notice Preview fee required to bridge shares back to source.
     */
    function previewFee(uint256 amount, address to) public view returns (uint256 fee) {
        Client.EVM2AnyMessage memory message = _buildMessage(amount, to);

        IRouterClient router = IRouterClient(this.getRouter());

        fee = router.getFee(sourceChainSelector, message);
    }

    //============================== CCIP RECEIVER ===============================

    /**
     * @notice Implement internal _ccipRecevie function logic.
     */
    function _processMessage(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        (uint256 amount, address to) = abi.decode(any2EvmMessage.data, (uint256, address));
        _mint(to, amount);
        emit BridgeFromSource(amount, to);
    }

    function _isSenderOk(bytes memory sender) internal view override returns (bool) {
        return abi.decode(sender, (address)) == targetSource;
    }

    function _isSourceChainOk(uint64 _sourceChainSelector) internal view override returns (bool) {
        return _sourceChainSelector == sourceChainSelector;
    }

    //============================== INTERNAL HELPER ===============================

    /**
     * @notice Build the CCIP message to send to source locker.
     */
    function _buildMessage(uint256 amount, address to) internal view returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(targetSource),
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
