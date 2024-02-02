// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";

/**
 * @title Morpho Blue Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Morpho Blue pairs for a Cellar.
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue throughout code.
 * @author 0xEinCodes, crispymangoes
 */
contract MorphoBlueCollateralAdaptor is BaseAdaptor, MorphoBlueHelperLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using MarketParamsLib for MarketParams;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams market)
    // Where:
    // `market` is the respective market used within Morpho Blue
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Removal of collateral causes Cellar Health Factor below what is required
     */
    error MorphoBlueCollateralAdaptor__HealthFactorTooLow(MarketParams market);

    /**
     * @notice Minimum Health Factor enforced after every removeCollateral() strategist function call.
     * @dev Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    /**
     * @param _morphoBlue immutable Morpho Blue contract (called `Morpho.sol` within Morpho Blue repo).
     * @param _healthFactor Minimum Health Factor that replaces minimumHealthFactor. If using new _healthFactor, it must be greater than minimumHealthFactor. See `BaseAdaptor.sol`.
     */
    constructor(address _morphoBlue, uint256 _healthFactor) MorphoBlueHelperLogic(_morphoBlue) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        morphoBlue = IMorpho(_morphoBlue);
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
        return keccak256(abi.encode("Morpho Blue Collateral Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits collateralToken to Morpho Blue market.
     * @param assets the amount of assets to provide as collateral on Morpho Blue.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @dev configurationData is NOT used.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho Blue.
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        _validateMBMarket(market, identifier(), false);
        ERC20 collateralToken = ERC20(market.collateralToken);
        _addCollateral(market, assets, collateralToken);
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     * NOTE: collateral withdrawal calls directly from users disallowed for now.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the collateralAsset position in corresponding Morpho Blue market.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return Cellar's balance of provided collateral to specified MB market.
     * @dev normal static call, thus msg.sender for most-likely Sommelier usecase is the calling cellar.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        Id id = MarketParamsLib.id(market);
        return _userCollateralBalance(id, msg.sender);
    }

    /**
     * @notice Returns collateral asset.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return The collateral asset in ERC20 type.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        return ERC20(market.collateralToken);
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     * @return Whether or not this position is a debt position.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to add collateral to the respective cellar position on specified MB Market, enabling borrowing.
     * @param _market identifier of a Morpho Blue market.
     * @param _collateralToDeposit The amount of `collateralToken` to add to specified MB market position.
     */
    function addCollateral(MarketParams memory _market, uint256 _collateralToDeposit) public {
        _validateMBMarket(_market, identifier(), false);
        ERC20 collateralToken = ERC20(_market.collateralToken);
        uint256 amountToDeposit = _maxAvailable(collateralToken, _collateralToDeposit);
        _addCollateral(_market, amountToDeposit, collateralToken);
    }

    /**
     * @notice Allows strategists to remove collateral from the respective cellar position on specified MB Market.
     * @param _market identifier of a Morpho Blue market.
     * @param _collateralAmount The amount of collateral to remove from specified MB market position.
     */
    function removeCollateral(MarketParams memory _market, uint256 _collateralAmount) public {
        _validateMBMarket(_market, identifier(), false);
        Id id = MarketParamsLib.id(_market);
        if (_collateralAmount == type(uint256).max) {
            _collateralAmount = _userCollateralBalance(id, address(this));
        }
        _removeCollateral(_market, _collateralAmount);
        if (minimumHealthFactor > (_getHealthFactor(id, _market))) {
            revert MorphoBlueCollateralAdaptor__HealthFactorTooLow(_market);
        }
    }

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Increment collateral amount in cellar account within specified MB Market.
     * @param _market The specified MB market.
     * @param _assets The amount of collateral to add to MB Market position.
     */
    function _addCollateral(MarketParams memory _market, uint256 _assets, ERC20 _collateralToken) internal virtual {
        // pass in collateralToken because we check maxAvailable beforehand to get assets, then approve ERC20
        _collateralToken.safeApprove(address(morphoBlue), _assets);
        morphoBlue.supplyCollateral(_market, _assets, address(this), hex"");
        // Zero out approvals if necessary.
        _revokeExternalApproval(_collateralToken, address(morphoBlue));
    }

    /**
     * @notice Decrement collateral amount in cellar account within Morpho Blue lending market
     * @param _market The specified MB market.
     * @param _assets The amount of collateral to remove from MB Market position.
     */
    function _removeCollateral(MarketParams memory _market, uint256 _assets) internal virtual {
        morphoBlue.withdrawCollateral(_market, _assets, address(this), address(this));
    }
}
