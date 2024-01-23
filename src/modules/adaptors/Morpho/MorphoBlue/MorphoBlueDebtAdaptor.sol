// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { SharesMathLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/SharesMathLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";

/**
 * @title Morpho Blue Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from Morpho Blue pairs.
 * @dev  *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue.
 * @author 0xEinCodes, crispymangoes
 */
contract MorphoBlueDebtAdaptor is BaseAdaptor, MorphoBlueHelperLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using SharesMathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams market)
    // Where:
    // `market` is the respective market used within Morpho Blue
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted tx that results in unhealthy cellar.
     */
    error MorphoBlueDebtAdaptor__HealthFactorTooLow(MarketParams market);

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
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
     * @return Identifier unique to this adaptor for a shared registry.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Morpho Blue Debt Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellar's balance of the respective MB market loanToken calculated from cellar borrow shares according to MB prod contracts.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return Cellar's balance of the respective MB market loanToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        Id id = MarketParamsLib.id(market);
        return _userBorrowBalance(id, msg.sender);
    }

    /**
     * @notice Returns `loanToken` from respective MB market.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return `loanToken` from respective MB market.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        return ERC20(market.loanToken);
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     * @return Whether or not this adaptor is in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to borrow assets from Morpho Blue.
     * @param _market identifier of a Morpho Blue market.
     * @param _amountToBorrow the amount of `loanToken` to borrow on the specified MB market.
     */
    function borrowFromMorphoBlue(MarketParams memory _market, uint256 _amountToBorrow) public {
        _validateMBMarket(_market, identifier(), true);
        Id id = MarketParamsLib.id(_market);
        _borrowAsset(_market, _amountToBorrow, address(this));
        if (minimumHealthFactor > (_getHealthFactor(id, _market))) {
            revert MorphoBlueDebtAdaptor__HealthFactorTooLow(_market);
        }
    }

    /**
     * @notice Allows strategists to repay loan debt on Morph Blue Lending Market. Make sure to call addInterest() beforehand to ensure we are repaying what is required.
     * @dev Uses `_maxAvailable` helper function, see `BaseAdaptor.sol`.
     * @param _market identifier of a Morpho Blue market.
     * @param _debtTokenRepayAmount The amount of `loanToken` to repay.
     * NOTE - MorphoBlue reverts w/ underflow/overflow error if trying to repay with more than what cellar has. That said, we will accomodate for times that strategists tries to pass in type(uint256).max.
     */
    function repayMorphoBlueDebt(MarketParams memory _market, uint256 _debtTokenRepayAmount) public {
        _validateMBMarket(_market, identifier(), true);
        Id id = MarketParamsLib.id(_market);
        accrueInterest(_market);
        ERC20 tokenToRepay = ERC20(_market.loanToken);
        uint256 debtAmountToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);
        tokenToRepay.safeApprove(address(morphoBlue), debtAmountToRepay);

        uint256 totalBorrowAssets = morphoBlue.totalBorrowAssets(id);
        uint256 totalBorrowShares = morphoBlue.totalBorrowShares(id);
        uint256 sharesToRepay = morphoBlue.borrowShares(id, address(this));
        uint256 assetsMax = sharesToRepay.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        if (debtAmountToRepay >= assetsMax) {
            _repayAsset(_market, sharesToRepay, 0, address(this));
        } else {
            _repayAsset(_market, 0, debtAmountToRepay, address(this));
        }

        _revokeExternalApproval(tokenToRepay, address(morphoBlue));
    }

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Helper function to borrow specific amount of `loanToken` in cellar account within specific MB market.
     * @param _market The specified MB market.
     * @param _borrowAmount The amount of borrowAsset to borrow.
     * @param _onBehalf The receiver of the amount of `loanToken` borrowed and receiver of debt accounting-wise.
     */
    function _borrowAsset(MarketParams memory _market, uint256 _borrowAmount, address _onBehalf) internal virtual {
        morphoBlue.borrow(_market, _borrowAmount, 0, _onBehalf, _onBehalf);
    }

    /**
     * @notice Helper function to repay specific MB market debt by an amount.
     * @param _market The specified MB market.
     * @param _sharesToRepay The amount of borrowShares to repay.
     * @param _onBehalf The address of the debt-account reduced due to this repayment within MB market.
     * @param _debtAmountToRepay The amount of debt asset to repay.
     * NOTE - See IMorpho.sol for more detail, but within the external function call to the Morpho Blue contract, repayment amount param can only be either in borrowToken or borrowShares. Users need to choose btw repaying specifying amount of borrowAsset, or borrowShares, which is reflected in this helper.
     */
    function _repayAsset(
        MarketParams memory _market,
        uint256 _sharesToRepay,
        uint256 _debtAmountToRepay,
        address _onBehalf
    ) internal virtual {
        if (_sharesToRepay != 0) {
            morphoBlue.repay(_market, 0, _sharesToRepay, _onBehalf, hex"");
        } else {
            morphoBlue.repay(_market, _debtAmountToRepay, 0, _onBehalf, hex"");
        }
    }
}
