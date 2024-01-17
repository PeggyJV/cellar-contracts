// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { MorphoBalancesLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoBalancesLib.sol";
import { MorphoLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/periphery/MorphoLib.sol";
import { MorphoBlueHelperLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHelperLogic.sol";
import { MarketParamsLib } from "src/interfaces/external/Morpho/MorphoBlue/libraries/MarketParamsLib.sol";

/**
 * @title Morpho Blue Supply Adaptor
 * @notice Allows Cellars to lend loanToken to respective Morpho Blue Lending Markets.
 * @dev adaptorData is the MarketParams struct, not Id. This is to test with market as the adaptorData.
 * @dev This adaptor is specifically for Morpho Blue Primitive contracts.
 *      To interact with a different version or custom market, a new
 *      adaptor will inherit from this adaptor
 *      and override the interface helper functions. MB refers to Morpho
 *      Blue throughout code.
 *
 * @author 0xEinCodes, crispymangoes
 */
contract MorphoBlueSupplyAdaptor is BaseAdaptor, MorphoBlueHelperLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(MarketParams market)
    // Where:
    // `market` is the respective market used within Morpho Blue
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(bool isLiquid)
    // Where:
    // `isLiquid` dictates whether the position is liquid or not
    // If true:
    //      position can support use withdraws
    // else:
    //      position can not support user withdraws
    //
    //====================================================================

    /**
     * @notice Attempted to interact with a Morpho Blue Lending Market that the Cellar is not using.
     */
    error MorphoBlueSupplyAdaptor__MarketPositionsMustBeTracked(MarketParams market);

    /**
     * @param _morphoBlue immutable Morpho Blue contract (called `Morpho.sol` within Morpho Blue repo).
     */
    constructor(address _morphoBlue) MorphoBlueHelperLogic(_morphoBlue) {
        morphoBlue = IMorpho(_morphoBlue);
    }

    // ============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Morpho Blue Supply Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Allows user to deposit into MB markets, only if Cellar has a MBSupplyAdaptorPosition as its holding position.
     * @dev Cellar must approve Morpho Blue to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Morpho Blue.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @dev configurationData is NOT used.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        ERC20 loanToken = ERC20(market.loanToken);
        loanToken.safeApprove(address(morphoBlue), assets);
        _deposit(market, assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(loanToken, address(morphoBlue));
    }

    /**
     * @notice Cellars must withdraw from Morpho Blue lending market, then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Morpho Blue lending market
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @param configurationData abi encoded bool indicating whether the position is liquid or not
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        // Run external receiver check.
        _externalReceiverCheck(receiver);
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        // Withdraw assets from Morpho Blue.
        _validateMBMarket(market);
        _withdraw(market, assets, receiver);
    }

    /**
     * @notice Returns the amount of loanToken that can be withdrawn.
     * @dev Compares loanToken supplied to loanToken borrowed to check for liquidity.
     *      - If loanToken balance is greater than liquidity available, it returns the amount available.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @param configurationData abi encoded bool indicating whether the position is liquid or not
     * @return withdrawableSupply liquid amount of `loanToken` cellar has lent to specified MB market.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256 withdrawableSupply) {
        bool isLiquid = abi.decode(configurationData, (bool));

        if (isLiquid) {
            MarketParams memory market = abi.decode(adaptorData, (MarketParams));
            (uint256 totalSupplyAssets, , uint256 totalBorrowAssets, ) = morphoBlue.expectedMarketBalances(market);
            if (totalBorrowAssets >= totalSupplyAssets) return 0;
            uint256 liquidSupply = totalSupplyAssets - totalBorrowAssets;
            uint256 cellarSuppliedBalance = morphoBlue.expectedSupplyAssets(market, msg.sender);
            withdrawableSupply = cellarSuppliedBalance > liquidSupply ? liquidSupply : cellarSuppliedBalance;
        } else return 0;
    }

    /**
     * @notice Returns the cellar's balance of the supplyToken position.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return Cellar's balance of the supplyToken position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        Id id = MarketParamsLib.id(market);
        return _userSupplyBalance(id, msg.sender);
    }

    /**
     * @notice Returns loanToken.
     * @param adaptorData adaptor data containing the abi encoded Morpho Blue market.
     * @return ERC20 loanToken.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        MarketParams memory market = abi.decode(adaptorData, (MarketParams));
        return ERC20(market.loanToken);
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
     * @notice Allows strategists to lend a specific amount for an asset on Morpho Blue market.
     * @param market identifier of a Morpho Blue market.
     * @param _assets the amount of loanToken to lend on specified MB market.
     */
    function lendToMorphoBlue(MarketParams memory market, uint256 _assets) public {
        _validateMBMarket(market);
        ERC20 loanToken = ERC20(market.loanToken);
        _assets = _maxAvailable(loanToken, _assets);
        loanToken.safeApprove(address(morphoBlue), _assets);
        _deposit(market, _assets, address(this));
        // Zero out approvals if necessary.
        _revokeExternalApproval(loanToken, address(morphoBlue));
    }

    /**
     * @notice Allows strategists to withdraw underlying asset plus interest.
     * @param market identifier of a Morpho Blue market.
     * @param _assets the amount of loanToken to withdraw from MB market
     */
    function withdrawFromMorphoBlue(MarketParams memory market, uint256 _assets) public {
        // Run external receiver check.
        _externalReceiverCheck(address(this));
        _validateMBMarket(market);
        Id _id = MarketParamsLib.id(market);
        if (_assets == type(uint256).max) {
            _accrueInterest(market);
            _assets = _userSupplyBalance(_id, address(this));
        }
        // Withdraw assets from Morpho Blue.
        _withdraw(market, _assets, address(this));
    }

    /**
     * @notice Allows a strategist to call `accrueInterest()` on a MB Market that the cellar is using.
     * @dev A strategist might want to do this if a MB market has not been interacted with
     *      in a while, and the strategist does not plan on interacting with it during a
     *      rebalance.
     * @dev Calling this can increase the share price during the rebalance,
     *      so a strategist should consider moving some assets into reserves.
     * @param market identifier of a Morpho Blue market.
     */
    function accrueInterest(MarketParams memory market) public {
        _validateMBMarket(market);
        _accrueInterest(market);
    }

    /**
     * @notice Validates that a given market is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     * @param _market MarketParams struct for a specific Morpho Blue market.
     */
    function _validateMBMarket(MarketParams memory _market) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_market)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoBlueSupplyAdaptor__MarketPositionsMustBeTracked(_market);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // General message on interface and virtual functions below: The Morpho Blue protocol is meant to be a primitive layer to DeFi, and so other projects may build atop of MB. These possible future projects may implement the same interface to simply interact with MB, and thus this adaptor is implementing a design that allows for future adaptors to simply inherit this "Base Morpho Adaptor" and override what they need appropriately to work with whatever project. Aspects that may be adjusted include using the flexible `bytes` param within `morphoBlue.supplyCollateral()` for example.

    // Current versions in use are just for the primitive Morpho Blue deployments.
    // IMPORTANT: Going forward, other versions will be renamed w/ descriptive titles for new projects extending off of these primitive contracts.
    //===============================================================================

    /**
     * @notice Deposit loanToken into specified MB lending market.
     * @param _market The specified MB market.
     * @param _assets The amount of `loanToken` to transfer to MB market.
     * @param _onBehalf The address that MB market records as having supplied this amount of `loanToken` as a lender.
     */
    function _deposit(MarketParams memory _market, uint256 _assets, address _onBehalf) internal virtual {
        morphoBlue.supply(_market, _assets, 0, _onBehalf, hex"");
    }

    /**
     * @notice Withdraw loanToken into specified MB lending market.
     * @param _market The specified MB Market
     * @param _assets The amount to withdraw
     * @param _onBehalf The address to which the Asset Tokens will be transferred
     */
    function _withdraw(MarketParams memory _market, uint256 _assets, address _onBehalf) internal virtual {
        morphoBlue.withdraw(_market, _assets, 0, address(this), _onBehalf);
    }
}
