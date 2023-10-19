// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";
import { CompoundV3ExtraLogic } from "src/modules/adaptors/Compound/v3/CompoundV3ExtraLogic.sol";

/**
 * @title Compound Lending Adaptor
 * @dev This adaptor is specifically for CompoundV3 contracts.
 *      See other Compound Adaptors if looking to interact with a different version.
 *      See CompoundV3DebtAdaptor for borrowing functionality.
 * @notice Allows Cellars to add Collateral to CompoundV3 Lending Markets. When adding collateral, CompoundV3 does not mint receiptTokens and keeps tracks via internal accounting in Proxy contract.
 * @author crispymangoes, 0xEinCodes
 */
contract CompoundV3CollateralAdaptor is BaseAdaptor, CompoundHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address compMarket, address asset)
    // Where:
    // `compMarket` is the CompoundV3 Lending Market address and `asset` is the address of the ERC20 that this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted a tx that would result in the Cellar to have too low of a health factor in the respective account with the specified Compound Lending Market (compMarket) and asset combination.
     */
    error CompoundV3CollateralAdaptor__HealthFactorTooLow(address compMarket, address asset);

    /**
     * @notice Attempted to deposit base token for respective lending market with collateral adaptor.
     */
    error CompoundV3CollateralAdaptor__CannotUseCollateralAdaptorForBaseToken(address compMarket, address asset);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every removeSupply() strategist function call.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(bool _accountForInterest, uint256 _healthFactor) CompoundV3ExtraLogic(_healthFactor) {
        ACCOUNT_FOR_INTEREST = _accountForInterest; // should be set to true since CompoundV3 protocol keeps amounts up to date.
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        minimumHealthFactor = _healthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("CompoundV3 Collateral Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve CompoundV3 Lending Market to spend its assets, then call supply to supply its assets.
     * @param amount the amount of assets to supply  to specified CompoundV3 Lending Market
     * @param adaptorData the CompMarket and Asset combo the Cellar position corresponds to
     * @dev configurationData is NOT used
     */
    function deposit(uint256 amount, bytes memory adaptorData, bytes memory) public override {
        // Supply assets to CompoundV3 Lending Market
        (CometInterface compMarket, ERC20 asset) = abi.decode(adaptorData, (CometInterface, ERC20));
        _checkForBaseToken(compMarket, asset);
        _validateCompMarketAndAsset(compMarket, asset);
        asset.safeApprove(address(compMarket), amount);
        compMarket.supply(asset, amount);

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(compMarket));
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position could be associated to a liquidable position within CompoundV3. Thus, user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the collateralAsset position.
     * @param adaptorData the CompMarket and Asset combo the Cellar position corresponds to
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (CometInterface compMarket, ERC20 asset) = abi.decode(adaptorData, (CometInterface, ERC20));
        return _userCollateralBalance(compMarket, address(asset));
    }

    /**
     * @notice Returns the position's collateral token.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (, ERC20 asset) = abi.decode(adaptorData, (, ERC20));
        return asset;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to provide Collateral to open new Borrow positions (via CompoundDebtAdaptor) or increase collateral
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param _asset The specified asset (ERC20) to provide as collateral
     * @param _amount The amount of `asset` token to transfer to CompMarket as collateral
     */
    function addCollateral(CometInterface _compMarket, ERC20 _asset, uint256 _amount) public {
        _validateCompMarketAndAsset(_compMarket, _asset);
        _checkForBaseToken(_compMarket, _asset);

        uint256 amountToAdd = _maxAvailable(_asset, _amount);
        address compMarketAddress = address(_compMarket);
        asset.safeApprove(compMarketAddress, amountToAdd);
        _compMarket.supply(_asset, amountToAdd);

        // Zero out approvals if necessary.
        _revokeExternalApproval(_asset, compMarketAddress);
    }

    /**
     * @notice Allows strategists to withdraw Collateral
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param _asset The specified asset (ERC20) to withdraw as collateral
     * @param _amount The amount of `asset` token to transfer to CompMarket as collateral
     */
    function withdrawCollateral(CometInterface _compMarket, ERC20 _asset, uint256 _amount) public {
        _validateCompMarketAndAsset(_compMarket, _asset);
        _checkForBaseToken(_compMarket, _asset);
        // withdraw collateral
        _compMarket.withdraw(address(_asset), _amount); // Collateral adjustment is checked against `isBorrowCollateralized(src)` in CompoundV3 and will revert if uncollateralized result. See `withdrawCollateral()` for more context in `Comet.sol`

        // Check if cellar account is unsafe after this collateral withdrawal tx, revert if they are
        if (_checkLiquidity(_compMarket) < 0)
            revert CompoundV3CollateralAdaptor__HealthFactorTooLow(address(_compMarket));
    }

    /// helpers
    function _checkForBaseToken(CometInterface _compMarket, ERC20 _asset) internal {
        if (address(asset) == _compMarket.baseToken())
            revert CompoundV3CollateralAdaptor__CannotUseCollateralAdaptorForBaseToken(
                address(_compMarket),
                address(_asset)
            );
    }
}
