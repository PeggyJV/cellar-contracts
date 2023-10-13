// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16; // TODO: update to 0.8.21

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";
import { CompoundHealthFactorLogic } from "src/modules/adaptors/Compound/v3/CompoundHealthFactorLogic.sol";

/**
 * @title Compound Lending Adaptor
 * @dev This adaptor is specifically for CompoundV3 contracts.
 *      See other Compound Adaptors if looking to interact with a different version.
 *      See CompoundV3DebtAdaptor for borrowing functionality.
 * @notice Allows Cellars to add Collateral to CompoundV3 Lending Markets. When adding collateral, CompoundV3 does not mint receiptTokens and keeps tracks via internal accounting in Proxy contract.
 * @author crispymangoes, 0xEinCodes
 * TODO: depending on what Compound team says back to us, we may switch to add functionality to supply `baseAsset` to lending markets vs just being a dedicated  CollateralAdaptor. For now, we are making a separate adaptor to handle supplying the `baseAsset` though.
 * TODO: use or remove minimumHealthFactor aspects
 */
contract CompoundV3CollateralAdaptor is BaseAdaptor, CompoundHealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address CompoundMarket, address asset)
    // Where:
    // `CompoundMarket` is the CompoundV3 Lending Market address and `asset` is the address of the ERC20 that this adaptor is working with,
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with a Compound Lending Market (compMarket) and asset combination the Cellar is not using.
     */
    error CompoundV3CollateralAdaptor__MarketAndAssetPositionsMustBeTracked(address compMarket, address asset);

    /**
     * @notice Attempted a tx that would result in the Cellar to have too low of a health factor in the respective account with the specified Compound Lending Market (compMarket) and asset combination.
     */
    error CompoundV3CollateralAdaptor__HealthFactorTooLow(address compMarket, address asset);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     * TODO: I believe it would be false.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every removeSupply() strategist function call.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    // TODO: might need a mapping of health factors for different assets because Compound accounts have different HFs for different assets (collateral). If this is needed it would be more-so for the internal calcs we do to ensure that any collateral adjustments don't affect the `minimumHealthFactor` which is a buffer above the minHealthFactor from Compound itself.
    constructor(bool _accountForInterest, uint256 _healthFactor) {
        ACCOUNT_FOR_INTEREST = _accountForInterest;
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
     * @param adaptorData adaptor data containing the abi encoded fToken
     * @dev configurationData is NOT used
     * TODO: If the `asset` is the `baseAsset` we may have to change this adaptor to not allow it. This is ONLY if we are having a separate adaptor to handle supplying the `baseAsset` to the CompMarket. Recall that `BaseAssets` are handled differently within CompoundV3: src (cellar) gets receiptToken, and more `baseAssets` over time upon redemption due to lending APY.
     */
    function deposit(uint256 amount, bytes memory adaptorData, bytes memory) public override {
        // Supply assets to CompoundV3 Lending Market
        (CometInterface compMarket, ERC20 asset) = abi.decode(adaptorData, (CometInterface, ERC20));
        _validateCompMarketAndAsset(compMarket, asset);
        asset.safeApprove(address(compMarket), amount);
        compMarket.supply(asset, amount);

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(compMarket));
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     * TODO: don't allow user withdrawals, strategist has to unwind out of positions involving CompoundV3.
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
        // withdraw collateral
        _compMarket.withdraw(address(_asset), _amount); // Collateral adjustment is checked against `isBorrowCollateralized(src)` in CompoundV3 and will revert if uncollateralized result. See `withdrawCollateral()` for more context in `Comet.sol`

        // TODO: add logic (incl. helper functions likely in HealthFactorLogic.sol) to calculate the new CR with this adjustment to compare against the `minimumHealthFactor` which should be higher than the minHealthFactor_CompMarket
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Validates that a given CompMarket and Asset are set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateCompMarketAndAsset(CometInterface _compMarket, ERC20 _asset) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_compMarket, _asset)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CompoundV3CollateralAdaptor__MarketAndAssetPositionsMustBeTracked(
                address(_compMarket),
                address(_asset)
            );
    }
}
