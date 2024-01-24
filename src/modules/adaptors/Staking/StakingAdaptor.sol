// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";

abstract contract StakingAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // interact with staking protocols.
    //====================================================================

    IWETH9 public immutable wrappedNative;

    constructor(IWETH9 _wrappedNative) {
        wrappedNative = _wrappedNative;
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users ERC20 assets by the time this function is called,
     *         so there is nothing to do.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of `token`.
     */
    //  TODO this should return the amount of native that you get out of teh claim even if the claim is pending.
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (ERC20 native, ERC20 derivative) = abi.decode(adaptorData, (ERC20, ERC20));
        (, , uint256 amount) = _getPendingWithdraw(msg.sender);
        return amount;
        // TODO check if there is a withdraw pending
        // If we are still waiting for it to be confirmed, return derivative balance
        // If withdraw period is over, return native balance
    }

    /**
     * @notice Returns `token`
     */
    //  TODO I think this should always return native, since once you deposit a lot of these protocols will save the exchange rate, so you get no more rewards.
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (ERC20 native, ERC20 derivative) = abi.decode(adaptorData, (ERC20, ERC20));
        (bool isRequestActive, bool isRequestPending, ) = _getPendingWithdraw(msg.sender);
        if (isRequestActive) {
            if (isRequestPending) {
                // We have an active request that is pending, return derivative
                return derivative;
            } else {
                // We have an active request that is matured, return native
                return native;
            }
        } else {
            // We do not have an active request, so balance will be zero, so just return native.
            return native;
        }
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    function mint(uint256 amount) external {
        amount = _maxAvailable(ERC20(address(wrappedNative)), amount);
        wrappedNative.withdraw(amount);

        _mint(amount);
    }

    function requestBurn(uint256 amount) external {
        (bool isRequestActive, , ) = _getPendingWithdraw(address(this));
        if (isRequestActive) revert("Can not start a new burn.");
    }

    function completeBurn() external {}

    // amount should either be zero if there is no active request, or the amount of the deriviative or native.
    function _getPendingWithdraw(
        address account
    ) internal view virtual returns (bool isRequestActive, bool isRequestPending, uint256 amount);

    function _mint(uint256 amount) internal virtual;

    function _wrap(uint256 amount) internal virtual;

    function _unwrap(uint256 amount) internal virtual;

    function _requestBurn(uint256 amount) internal virtual;

    function _completeBurn(uint256 amount) internal virtual;

    // TODO I actually think this contract should ONLY report the native balance, cuz once a request is made, we stop accruing rewards
    // also I dont think there is a way to cancel a requeset.
}
