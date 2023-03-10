// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken } from "src/interfaces/external/IEuler.sol";
import { EulerBaseAdaptor } from "src/modules/adaptors/Euler/EulerBaseAdaptor.sol";

/**
 * @title Euler eToken Adaptor
 * @notice Allows Cellars to interact with Euler eToken positions.
 * @author crispymangoes
 */
contract EulerETokenAdaptor is BaseAdaptor, EulerBaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(IEulerToken eToken, uint256 subAccountId)
    // Where:
    // `eToken` is the eToken address position this adaptor is working with
    // `subAccountId` is the sub account id the position uses
    //================= Configuration Data Specification =================
    // NONE
    // **************************** IMPORTANT ****************************
    // eToken positions have two unique states, the first one (when eToken is being used as collateral)
    // restricts all user withdraws, but allows strategists to take out loans against eToken collateral
    // The second state allows users withdraws, but the eTokens can NOT be used to back loans.
    //====================================================================

    /**
     * @notice Attempted withdraw would lower Cellar health factor too low.
     */
    error EulerETokenAdaptor__HealthFactorTooLow();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Euler eToken Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Euler to spend its assets, then call deposit to lend its assets.
     * @notice `depositToEuler` does expose `_maxAvailable` logic to user actions, but in order
     *         for `_maxAvailable` to change the amount being deposited, the amount must be type(uint256).max
     *         so the user would have had to pass a transfer of type(uint256).max assets into the cellar before
     *         this, which means the cellar would be holding type(uint256).max assets so `_maxAvailable` would not
     *         change the amount.
     * @param assets the amount of assets to lend on Euler
     * @param adaptorData adaptor data containing the abi encoded eToken, and sub account id
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));

        ERC20 underlying = ERC20(markets().eTokenToUnderlying(address(eToken)));
        underlying.safeApprove(euler(), assets);
        IEulerEToken(eToken).deposit(subAccountId, assets);

        // Zero out approvals if necessary.
        if (underlying.allowance(address(this), address(euler())) > 0) underlying.safeApprove(address(euler()), 0);
    }

    /**
     * @notice Cellars can only withdraw from Euler if the asset is not being used as collateral for a loan.
     *         This way we can prevent users from being able to manipulate a Cellars HF.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Euler
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded eToken, and sub account id
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));
        ERC20 underlying = ERC20(markets().eTokenToUnderlying(address(eToken)));

        address[] memory entered = markets().getEnteredMarkets(_getSubAccount(address(this), subAccountId));
        for (uint256 i; i < entered.length; ++i) {
            if (entered[i] == address(underlying)) revert BaseAdaptor__UserWithdrawsNotAllowed();
        }

        eToken.withdraw(subAccountId, assets);

        underlying.safeTransfer(receiver, assets);
    }

    /**
     * @notice Reports withdrawable assets from Euler.
     *         If asset is being used as collateral, reports zero.
     *         else reports the `balanceOfUnderlying` for the asset.
     * @param adaptorData adaptor data containing the abi encoded eToken, and sub account id
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));
        ERC20 underlying = ERC20(eToken.underlyingAsset());

        bool marketEntered;
        address subAccount = _getSubAccount(msg.sender, subAccountId);

        address[] memory entered = markets().getEnteredMarkets(subAccount);
        for (uint256 i; i < entered.length; ++i) {
            if (entered[i] == address(underlying)) {
                marketEntered = true;
                break;
            }
        }

        return marketEntered ? 0 : eToken.balanceOfUnderlying(subAccount);
    }

    /**
     * @notice Returns the cellars balance of the positions underlying asset.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));

        return eToken.balanceOfUnderlying(_getSubAccount(msg.sender, subAccountId));
    }

    /**
     * @notice Returns the positions eToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IEulerEToken eToken = abi.decode(adaptorData, (IEulerEToken));

        return ERC20(eToken.underlyingAsset());
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Euler.
     * @dev `_maxAvailable` is not used because Euler supports the logic on its own.
     * @param underlying the ERC20 token to lend on Euler
     * @param subAccountId the sub account id to lend assets on
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Euler
     */
    function depositToEuler(ERC20 underlying, uint256 subAccountId, uint256 amountToDeposit) public {
        // Grab eToken from Euler markets, and verify there is a valid market.
        address eToken = markets().underlyingToEToken(address(underlying));
        if (eToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        amountToDeposit = _maxAvailable(underlying, amountToDeposit);
        underlying.safeApprove(euler(), amountToDeposit);
        IEulerEToken(eToken).deposit(subAccountId, amountToDeposit);

        // Zero out approvals if necessary.
        if (underlying.allowance(address(this), address(euler())) > 0) underlying.safeApprove(address(euler()), 0);
    }

    /**
     * @notice Allows strategists to withdraw assets from Euler.
     * @param underlying the ERC20 token to withdraw from Euler
     * @param subAccountId the sub account id to withdraw assets from
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Euler
     */
    function withdrawFromEuler(ERC20 underlying, uint256 subAccountId, uint256 amountToWithdraw) public {
        // Grab eToken from Euler markets, and verify there is a valid market.
        address eToken = markets().underlyingToEToken(address(underlying));
        if (eToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        IEulerEToken(eToken).withdraw(subAccountId, amountToWithdraw);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMIN()) revert EulerETokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategist to enter markets.
     * @dev Doing so means `eToken` can be used as collateral, and user withdraws are not allowed.
     */
    function enterMarket(ERC20 underlying, uint256 subAccountId) public {
        // Grab eToken from Euler markets, and verify there is a valid market.
        address eToken = markets().underlyingToEToken(address(underlying));
        if (eToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        markets().enterMarket(subAccountId, address(underlying));
    }

    /**
     * @notice Allows strategists to exit markets.
     * @dev Doing so means the `eToken` can not be used as collateral, so user withdraws are allowed.
     */
    function exitMarket(ERC20 underlying, uint256 subAccountId) public {
        // Grab eToken from Euler markets, and verify there is a valid market.
        address eToken = markets().underlyingToEToken(address(underlying));
        if (eToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        markets().exitMarket(subAccountId, address(underlying));

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMIN()) revert EulerETokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to transfer eTokens between subAccounts.
     * @dev `_getSubAccount` will revert if a sub account id greater than 255 is used.
     */
    function transferETokensBetweenSubAccounts(ERC20 underlying, uint256 from, uint256 to, uint256 amount) public {
        // Grab eToken from Euler markets, and verify there is a valid market.
        address eToken = markets().underlyingToEToken(address(underlying));
        if (eToken == address(0)) revert EulerBaseAdaptor__UnderlyingNotSupported(address(underlying));

        ERC20(eToken).safeTransferFrom(_getSubAccount(address(this), from), _getSubAccount(address(this), to), amount);
    }
}
