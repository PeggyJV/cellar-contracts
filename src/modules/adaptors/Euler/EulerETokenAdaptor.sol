// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken } from "src/interfaces/external/IEuler.sol";

/**
 * @title Euler eToken Adaptor
 * @notice Allows Cellars to interact with Euler aToken positions.
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
    // restricts all user deposits/withdraws, but allows strategists to take out loans against eToken collateral
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
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
        return keccak256(abi.encode("Euler eToken Adaptor V 0.0"));
    }

    function markets() internal pure returns (IEulerMarkets) {
        return IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    }

    function exec() internal pure returns (IEulerExec) {
        return IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);
    }

    function euler() internal pure returns (address) {
        return 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    }

    /**
     * @notice Minimum HF enforced after every eToken withdraw/market exiting.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.2e18;
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Euler
     * @param adaptorData adaptor data containining the abi encoded aToken
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
     @notice Cellars must withdraw from Euler, check if a minimum health factor is specified
     *       then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Euler
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containining the abi encoded aToken

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
        // TODO does this always withdraw `assets`?
        eToken.withdraw(subAccountId, assets);

        underlying.transfer(receiver, assets);
    }

    /**
     * @notice Uses configurartion data minimum health factor to calculate withdrawable assets from Euler.
     * @dev Applies a `cushion` value to the health factor checks and calculation.
     *      The goal of this is to minimize scenarios where users are withdrawing a very small amount of
     *      assets from Euler. This function returns zero if
     *      -minimum health factor is NOT set.
     *      -the current health factor is less than the minimum health factor + 2x `cushion`
     *      Otherwise this function calculates the withdrawable amount using
     *      minimum health factor + `cushion` for its calcualtions.
     * @dev It is possible for the math below to lose a small amount of precision since it is only
     *      maintaining 18 decimals during the calculation, but this is desired since
     *      doing so lowers the withdrawable from amount which in turn raises the health factor.
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
     * @notice Returns the cellars balance of the positions aToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IEulerEToken eToken, uint256 subAccountId) = abi.decode(adaptorData, (IEulerEToken, uint256));

        return eToken.balanceOfUnderlying(_getSubAccount(msg.sender, subAccountId));
    }

    /**
     * @notice Returns the positions aToken underlying asset.
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
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToDeposit the token to lend on Euler
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Euler.
     */
    function depositToEuler(
        IEulerEToken tokenToDeposit,
        uint256 subAccountId,
        uint256 amountToDeposit
    ) public {
        ERC20 underlying = ERC20(tokenToDeposit.underlyingAsset());
        amountToDeposit = _maxAvailable(underlying, amountToDeposit);
        underlying.safeApprove(euler(), amountToDeposit);
        tokenToDeposit.deposit(subAccountId, amountToDeposit);
    }

    /**
     * @notice Allows strategists to withdraw assets from Euler.
     * @param tokenToWithdraw the token to withdraw from Euler.
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

    function enterMarket(IEulerEToken eToken, uint256 subAccountId) public {
        markets().enterMarket(subAccountId, eToken.underlyingAsset());
    }

    function exitMarket(IEulerEToken eToken, uint256 subAccountId) public {
        markets().exitMarket(subAccountId, eToken.underlyingAsset());

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _calculateHF(address(this));
        if (healthFactor < HFMIN()) revert EulerETokenAdaptor__HealthFactorTooLow();
    }

    function transferETokensBetweenSubAccounts(
        IEulerEToken eToken,
        uint256 from,
        uint256 to,
        uint256 amount
    ) public {
        bool success = eToken.transferFrom(
            _getSubAccount(address(this), from),
            _getSubAccount(address(this), to),
            amount
        );

        require(success, "TransferFrom Failed");
    }

    // TODO health score = risk adjusted collateral / risk adjusted liabilities
    function _calculateHF(address target) internal view returns (uint256) {
        IEulerExec.AssetLiquidity[] memory assets = exec().detailedLiquidity(target);
        uint256 valueWeightedCollateralFactor;
        uint256 totalCollateral;
        uint256 totalLiabilites;
        for (uint256 i; i < assets.length; ++i) {
            totalLiabilites += assets[i].status.liabilityValue;
            if (assets[i].status.collateralValue > 0) {
                totalCollateral += assets[i].status.collateralValue;
                IEuler.AssetConfig memory config = markets().underlyingToAssetConfig(assets[i].underlying);
                valueWeightedCollateralFactor += assets[i].status.collateralValue.mulDivDown(
                    config.collateralFactor,
                    4e9
                );
                // 4e9 is the max possible value CF can be, so a CF of 1 would equal 4e9.
                // TODO is the 4e9 assumption correct.
            }
        }
        // Left here for derivation of actual return value.
        // uint256 avgCollateralFactor = valueWeightedCollateralFactor / totalCollateral;
        // return totalCollateral.mulDivDown(avgCollateralFactor, totalLiabilites);
        return valueWeightedCollateralFactor.mulDivDown(1e18, totalLiabilites);
    }

    function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
        require(subAccountId < 256, "e/sub-account-id-too-big");
        return address(uint160(primary) ^ uint160(subAccountId));
    }
}
