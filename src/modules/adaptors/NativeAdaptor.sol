// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";

// TODO add a brief overview for each protocols staking/unstaking process.
/**
 * @title Native Adaptor
 * @notice Allows Cellars to account for value in Native asset, and interact with native asset.
 * @author crispymangoes
 */
contract NativeAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    // ========================================= GLOBAL FUNCTIONS =========================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Native Adaptor V 0.0"));
    }

    //========================================= ERRORS =========================================

    error NativeAdaptor__ZeroAmount();

    //========================================= IMMUTABLES ==========================================

    /**
     * @notice The wrapper contract for the native asset.
     */
    IWETH9 public immutable nativeWrapper;

    constructor(address _nativeWrapper) {
        nativeWrapper = IWETH9(_nativeWrapper);
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice This adaptor does not support user deposits.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice This adaptor does not support user withdraws.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This adaptor is not user withdrawable.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of `primitive` that is unstaking.
     */
    function balanceOf(bytes memory) public view override returns (uint256) {
        return msg.sender.balance;
    }

    /**
     * @notice Returns `primitive`
     */
    function assetOf(bytes memory) public view override returns (ERC20) {
        return ERC20(address(nativeWrapper));
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows a strategist to wrap a native asset.
     * @param amount the amount of native to wrap
     */
    function wrap(uint256 amount) external virtual {
        if (amount == 0) revert NativeAdaptor__ZeroAmount();

        if (amount == type(uint256).max) {
            amount = address(this).balance;
        }

        nativeWrapper.deposit{ value: amount }();
    }

    /**
     * @notice Allows a strategist to unwrap a wrapped native asset.
     * @param amount the amount of wrapped native to unwrap
     */
    function unwrap(uint256 amount) external virtual {
        if (amount == 0) revert NativeAdaptor__ZeroAmount();

        amount = _maxAvailable(ERC20(address(nativeWrapper)), amount);

        nativeWrapper.withdraw(amount);
    }
}
