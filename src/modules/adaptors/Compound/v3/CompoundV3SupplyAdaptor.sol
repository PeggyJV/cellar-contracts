// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";
import { CompoundV3ExtraLogic } from "src/modules/adaptors/Compound/v3/CompoundV3ExtraLogic.sol";

/**
 * @title CompoundV3 Supply Adaptor
 * @dev This adaptor is specifically for CompoundV3 contracts. Recall that accounts within CompoundV3 cannot hold a 'supplyBaseAsset' position AND open a borrow position.
 *      See other Compound Adaptors if looking to interact with a different version.
 *      See CompoundV3DebtAdaptor for borrowing functionality.
 *      See CompoundV3CollateralAdaptor for collateral provision functionality.
 * @notice Allows Cellars to supply `BaseAsset` to CompoundV3 Lending Markets. When adding `BaseAsset`, CompoundV3 mints receiptTokens to the Cellar.
 * @author crispymangoes, 0xEinCodes
 */
contract CompoundV3SupplyAdaptor is BaseAdaptor, CompoundV3ExtraLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address compMarket)
    // Where:
    // `compMarket` is the CompoundV3 Lending Market address that this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to supply `baseAsset` when Cellar has an open borrow position.
     */
    error CompoundV3SupplyAdaptor__AccountHasOpenBorrow(address compMarket);

    /**
     * @notice Attempted to withdraw `baseAsset` when Cellar has no open supply position in lending market.
     */
    error CompoundV3SupplyAdaptor__AccountHasNoSupplyPosition(address compMarket);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("CompoundV3 Supply Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve CompoundV3 Lending Market to spend its assets, then call supply to supply its assets.
     * @param amount the amount of `baseAssets` to lend on CompoundV3
     * @param adaptorData adaptor data containing the abi encoded fToken
     * @dev configurationData is NOT used
     * TODO: sort out if it is a good design to have strategists able to supply baseAsset even if they have collateral, BUT NOT a borrow position. Alternatively, we have it so they cannot supply BaseAsset if they even have a collateral position (meaning collateral position leads to borrow position). For now, I'll design it so it only checks if there is debt already, if not, then we'll allow supply of the baseAsset. But if it wants to open a borrow position, it has to have a supply balance of zero.
     */
    function deposit(uint256 amount, bytes memory adaptorData, bytes memory) public override {
        // Supply assets to CompoundV3 Lending Market
        CometInterface compMarket = abi.decode(adaptorData, (CometInterface));
        _validateCompMarket(compMarket);
        _checkBorrowPosition(compMarket);
        ERC20 baseAsset = ERC20(compMarket.baseToken());
        baseAsset.safeApprove(address(compMarket), amount);
        compMarket.supply(baseAsset, amount);
        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(compMarket));
    }

    /**
     * @notice Cellar must withdraw from CompoundV3 Lending Market, then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from CompoundV3 Lending Market
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded fToken
     * @dev configurationData is NOT used
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public pure override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);
        // Withdraw assets from CompoundV3 Lending Market
        CometInterface compMarket = abi.decode(adaptorData, CometInterface);

        _validateCompMarket(compMarket);
        _checkSupplyPosition(compMarket);
        ERC20 baseAsset = ERC20(compMarket.baseToken());

        uint256 availableBaseAsset = compMarket.balanceOf(address(this));
        _amount = availableBaseAsset > _amount ? availableBaseAsset : _amount;
        // withdraw collateral
        compMarket.withdraw(address(baseAsset), _amount);
    }

    /**
     * @notice Returns the amount of `baseAsset` that can be withdrawn.
     * @dev TODO: need to see how CompoundV3 handles checking withdrawing `baseAsset` when there are borrow positions on it. Are the `baseAsset` fully liquid? Compares `baseAsset` supplied to `baseAsset` borrowed to check for liquidity.
     *      - If `baseAsset` balance is greater than liquidity available, it returns the amount available.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        // NOTE: for now, assuming it can be withdrawn at any time.
        CometInterface compMarket = abi.decode(adaptorData, CometInterface);
        return compMarket.balanceOf(address(this));
    }

    /**
     * @notice Returns the cellar's balance of the CompoundV3Supply position.
     * @param adaptorData the CompMarket the Cellar position corresponds to
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CometInterface compMarket = abi.decode(adaptorData, CometInterface);
        return compMarket.balanceOf(address(this));
    }

    /**
     * @notice Returns the specific CompoundV3 Lending Market `baseAsset` token.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CometInterface compMarket = abi.decode(adaptorData, CometInterface);
        return ERC20(compMarket.baseToken());
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to supply `baseAsset` to CompoundV3 Lending Market
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param _amount The amount of `baseAsset` token to supply to compMarket
     */
    function supply(CometInterface _compMarket, uint256 _amount) public {
        _validateCompMarket(_compMarket);
        _checkBorrowPosition(_compMarket);
        ERC20 baseAsset = ERC20(_compMarket.baseToken());
        uint256 amountToAdd = _maxAvailable(baseAsset, _amount);
        address compMarketAddress = address(_compMarket);
        asset.safeApprove(compMarketAddress, amountToAdd);
        _compMarket.supply(baseAsset, amountToAdd);
        // Zero out approvals if necessary.
        _revokeExternalApproval(baseAsset, compMarketAddress);
    }

    /**
     * @notice Allows strategists to withdraw supply assets
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param _amount The amount of `asset` token to transfer to CompMarket as collateral
     */
    function withdrawSupply(CometInterface _compMarket, uint256 _amount) public {
        _validateCompMarket(_compMarket);
        _checkSupplyPosition(_compMarket);
        ERC20 baseAsset = ERC20(_compMarket.baseToken());
        uint256 availableBaseAsset = _compMarket.balanceOf(address(this));
        _amount = availableBaseAsset > _amount ? availableBaseAsset : _amount;
        // withdraw collateral
        _compMarket.withdraw(address(baseAsset), _amount);
    }

    /// helpers

    function _checkSupplyPosition(CometInterface _compMarket) internal {
        if (_compMarket.balanceOf(address(this)) == 0)
            revert CompoundV3SupplyAdaptor__AccountHasNoSupplyPosition(address(_compMarket));
    }

    function _checkBorrowPosition(CometInterface _compMarket) internal {
        if (_compMarket.borrowBalanceOf(address(this)) != 0)
            revert CompoundV3SupplyAdaptor__AccountHasOpenBorrow(address(_compMarket));
    }
}
