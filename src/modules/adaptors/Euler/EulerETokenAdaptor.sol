// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken } from "src/interfaces/external/IEuler.sol";

/**
 * @title Euler eToken Adaptor
 * @notice Allows Cellars to interact with Euler eToken positions.
 * @author crispymangoes
 */
contract EulerETokenAdaptor is BaseAdaptor {
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

    /**
     * @notice Attempted to use an invalid subAccountId.
     */
    error EulerETokenAdaptor__InvalidSubAccountId();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Euler eToken Adaptor V 0.0"));
    }

    /**
     * @notice The Euler Markets contract on Ethereum Mainnet.
     */
    function markets() internal pure returns (IEulerMarkets) {
        return IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    }

    /**
     * @notice The Euler Exec contract on Ethereum Mainnet.
     */
    function exec() internal pure returns (IEulerExec) {
        return IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);
    }

    /**
     * @notice The Euler contract on Ethereum Mainnet.
     */
    function euler() internal pure returns (address) {
        return 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    }

    /**
     * @notice Minimum HF enforced after every eToken withdraw/market exit.
     * @dev A low `HFMIN` is required for strategist to run leveraged strategies,
     *      where the collateral and borrow token are the same.
     *      This does pose a risk of strategists intentionally making their Cellar vulnerable to liquidation
     *      but this is mitigated because of the following
     *      - Euler liquidations are gradual, and increase in size as the position becomes worse, so even if
     *        a Cellar's health factor is slightly below 1, the value lost from liquidation is much less
     *        compared to an Aave or Compound liquidiation
     *      - Given that the MEV liquidation space is so competitive it is extremely unlikely that a strategist
     *        would be able to consistently be the one liquidating the Cellar.
     *      - If a Cellar is constantly being liquidated because of a malicious strategist intentionally lowering the HF,
     *        users will leave the Cellar, and the strategist will lose future recurring income.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.01e18;
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Euler to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Euler
     * @param adaptorData adaptor data containing the abi encoded eToken, and sub account id
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));
        ERC20 underlying = ERC20(eToken.underlyingAsset());

        // Deposit assets to Euler.
        underlying.safeApprove(euler(), assets);
        eToken.deposit(subAccountId, assets);
    }

    /**
     * @notice Cellars can only withdraw from Euler if the asset is not being used as collateral for a loan.
     *         This way we can prevent users from being able to manipulate a Cellars HF.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Euler
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded eToken, and sub account id
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));
        ERC20 underlying = ERC20(eToken.underlyingAsset());

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
     * @param tokenToDeposit the token to lend on Euler
     * @param subAccountId the sub account id to lend assets on
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Euler
     */
    function depositToEuler(
        IEulerEToken tokenToDeposit,
        uint256 subAccountId,
        uint256 amountToDeposit
    ) public {
        ERC20 underlying = ERC20(tokenToDeposit.underlyingAsset());
        underlying.safeApprove(euler(), amountToDeposit);
        tokenToDeposit.deposit(subAccountId, amountToDeposit);
    }

    /**
     * @notice Allows strategists to withdraw assets from Euler.
     * @param tokenToWithdraw the token to withdraw from Euler
     * @param subAccountId the sub account id to withdraw assets from
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Euler
     */
    function withdrawFromEuler(
        IEulerEToken tokenToWithdraw,
        uint256 subAccountId,
        uint256 amountToWithdraw
    ) public {
        tokenToWithdraw.withdraw(subAccountId, amountToWithdraw);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(_getSubAccount(address(this), subAccountId));
        if (healthFactor < HFMIN()) revert EulerETokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategist to enter markets.
     * @dev Doing so means `eToken` can be used as collateral, and user withdraws are not allowed.
     */
    function enterMarket(IEulerEToken eToken, uint256 subAccountId) public {
        markets().enterMarket(subAccountId, eToken.underlyingAsset());
    }

    /**
     * @notice Allows strategists to exit markets.
     * @dev Doing so means the `eToken` can not be used as collateral, so user withdraws are allowed.
     */
    function exitMarket(IEulerEToken eToken, uint256 subAccountId) public {
        markets().exitMarket(subAccountId, eToken.underlyingAsset());

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(address(this));
        if (healthFactor < HFMIN()) revert EulerETokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to transfer eTokens between subAccounts.
     * @dev `_getSubAccount` will revert if a sub account id greater than 255 is used.
     */
    function transferETokensBetweenSubAccounts(
        IEulerEToken eToken,
        uint256 from,
        uint256 to,
        uint256 amount
    ) public {
        ERC20(address(eToken)).safeTransferFrom(
            _getSubAccount(address(this), from),
            _getSubAccount(address(this), to),
            amount
        );
    }

    /**
     * @notice Calculate the `target`s health factor.
     * @dev Returns type(uint256).max if there is no outstanding debt.
     */
    function _calculateHF(address target) internal view returns (uint256) {
        IEulerExec.LiquidityStatus memory status = exec().liquidity(target);

        // If target has no debt, report type(uint256).max.
        if (status.liabilityValue == 0) return type(uint256).max;

        // Else calculate actual health factor.
        return status.collateralValue.mulDivDown(1e18, status.liabilityValue);
    }

    /**
     * @notice Helper function to compute the sub account address given the primary account, and sub account Id.
     */
    function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
        if (subAccountId >= 256) revert EulerETokenAdaptor__InvalidSubAccountId();
        return address(uint160(primary) ^ uint160(subAccountId));
    }
}
