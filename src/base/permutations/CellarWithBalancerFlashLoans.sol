// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20, Math, SafeTransferLib } from "src/base/Cellar.sol";
import { IFlashLoanRecipient, IERC20 } from "@balancer/interfaces/contracts/vault/IFlashLoanRecipient.sol";

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

contract CellarWithBalancerFlashLoans is Cellar, IFlashLoanRecipient {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    /**
     * @notice The Balancer Vault contract on current network.
     * @dev For mainnet use 0xBA12222222228d8Ba445958a75a0704d566BF2C8.
     */
    address public immutable balancerVault;

    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut,
        uint192 _shareSupplyCap,
        address _balancerVault
    )
        Cellar(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            _strategistPlatformCut,
            _shareSupplyCap
        )
    {
        balancerVault = _balancerVault;
    }

    // ========================================= Balancer Flash Loan Support =========================================
    /**
     * @notice External contract attempted to initiate a flash loan.
     */
    error Cellar__ExternalInitiator();

    /**
     * @notice receiveFlashLoan was not called by Balancer Vault.
     */
    error Cellar__CallerNotBalancerVault();

    /**
     * @notice Allows strategist to utilize balancer flashloans while rebalancing the cellar.
     * @dev Balancer does not provide an initiator, so instead insure we are in the `callOnAdaptor` context
     *      by reverting if `blockExternalReceiver` is false.
     */
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external {
        if (msg.sender != balancerVault) revert Cellar__CallerNotBalancerVault();
        if (!blockExternalReceiver) revert Cellar__ExternalInitiator();

        AdaptorCall[] memory data = abi.decode(userData, (AdaptorCall[]));

        // Run all adaptor calls.
        _makeAdaptorCalls(data);

        // Approve pool to repay all debt.
        for (uint256 i = 0; i < amounts.length; ++i) {
            ERC20(address(tokens[i])).safeTransfer(balancerVault, (amounts[i] + feeAmounts[i]));
        }
    }
}
