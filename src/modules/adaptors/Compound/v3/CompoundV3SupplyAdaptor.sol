// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16; // TODO: update to 0.8.21

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";

/**
 * @title Compound Supply Adaptor
 * @dev This adaptor is specifically for CompoundV3 contracts. Recall that accounts within CompoundV3 cannot hold a 'supplyBaseAsset' position AND open a borrow position.
 *      See other Compound Adaptors if looking to interact with a different version.
 *      See CompoundV3DebtAdaptor for borrowing functionality.
 *      See CompoundV3CollateralAdaptor for collateral provision functionality.
 * @notice Allows Cellars to supply `BaseAsset` to CompoundV3 Lending Markets. When adding `BaseAsset`, CompoundV3 mints receiptTokens to the Cellar.
 * @author crispymangoes, 0xEinCodes
 * NOTE: is it better to query for the `baseAsset` per compound lending market or have it stored in here? I guess just query cause there could be more lending markets in the future? Also we want this to be agnostic to other chains too.
 */
contract CompoundV3SupplyAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address CompoundMarket)
    // Where:
    // `CompoundMarket` is the CompoundV3 Lending Market address that this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with a Compound Lending Market (compMarket) the Cellar is not using.
     */
    error CompoundV3SupplyAdaptor__MarketPositionsMustBeTracked(address compMarket);

    /**
     * @notice Attempted to supply `baseAsset` when Cellar has an open borrow position.
     */
    error CompoundV3SupplyAdaptor__AccountHasOpenBorrow(address compMarket);

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
     * TODO: If the `asset` isn't the `baseAsset` then this function will revert.
     * TODO: If the calling cellar already has an open borrow position or collateral position, we need to revert because Strategist must use other adaptors when dealing with collateral and borrow positions. CHECK to see if it reverts on its own within Compound via testing.
     */
    function deposit(uint256 amount, bytes memory adaptorData, bytes memory) public override {
        // Supply assets to CompoundV3 Lending Market
        CometInterface compMarket = abi.decode(adaptorData, (CometInterface));
        _validateCompMarket(compMarket);
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
        ERC20 baseAsset = ERC20(_compMarket.baseToken());

        uint256 amountToAdd = _maxAvailable(baseAsset, _amount);

        address compMarketAddress = address(_compMarket);
        asset.safeApprove(compMarketAddress, amountToAdd);
        _compMarket.supply(baseAsset, amountToAdd);

        // Zero out approvals if necessary.
        _revokeExternalApproval(baseAsset, compMarketAddress);
    }

    /**
     * @notice Allows strategists to withdraw Collateral
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param _asset The specified asset (ERC20) to withdraw as collateral
     * @param _amount The amount of `asset` token to transfer to CompMarket as collateral
     */
    function withdrawCollateral(CometInterface _compMarket, uint256 _amount) public {
        _validateCompMarket(_compMarket);
        ERC20 baseAsset = ERC20(_compMarket.baseToken());
        uint256 availableBaseAsset = _compMarket.balanceOf(address(this));
        _amount = availableBaseAsset > _amount ? availableBaseAsset : _amount;
        // withdraw collateral
        _compMarket.withdraw(address(baseAsset), _amount);
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Validates that a given CompMarket and Asset are set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateCompMarket(CometInterface _compMarket) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_compMarket)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CompoundV3SupplyAdaptor__MarketPositionsMustBeTracked(address(_compMarket));
    }
}
