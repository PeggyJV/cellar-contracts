// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math, Cellar, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";
import { CompoundV3Helper } from "src/modules/adaptors/Compound/V3/CompoundV3Helper.sol";

/**
 * @title Compound V3 Borrow Adaptor
 * @notice Allows Cellars to borrow the base token from Compound V3.
 * @author crispymangoes
 */
contract CompoundV3BorrowAdaptor is BaseAdaptor, CompoundV3Helper {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Comet comet)
    // Where:
    // `comet` is the underling Compound V3 Comet this adaptor is working with
    // `collateralAsset` is the CompoundV3 asset to use as collateral.
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted action would lower health factor below adaptor minimum.
     */
    error BorrowAdaptor__HealthFactorTooLow();

    /**
     * @notice Attempted to borrow while supplying assets.
     */
    error BorrowAdaptor___TryingToBorrowWhileSupplying();

    /**
     * @notice Strategist attempted to use an invalid Comet address.
     */
    error BorrowAdaptor___InvalidComet(address comet);

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        minimumHealthFactor = minHealthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Compound V3 Borrow Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Not supported.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Not supported.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice Reports 0, as borrowing from Compound V3 would lower the health factor of the cellar.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of comet base token borrowed.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IComet comet = abi.decode(adaptorData, (IComet));
        return comet.borrowBalanceOf(msg.sender);
    }

    /**
     * @notice Returns `comet.baseToken()`
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IComet comet = abi.decode(adaptorData, (IComet));
        return comet.baseToken();
    }

    /**
     * @notice This adaptor returns debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to borrow the base token from a comet.
     * @dev It is important that the strategist borrows at least the min borrow amount.
     */
    function borrowBase(IComet comet, uint256 assets) external {
        _verifyComet(comet);

        uint256 baseAssets = comet.balanceOf(address(this));

        if (baseAssets != 0) revert BorrowAdaptor___TryingToBorrowWhileSupplying();

        ERC20 base = comet.baseToken();

        comet.withdraw(address(base), assets);

        uint256 healthFactor = getAccountHealthFactor(comet, address(this));
        if (healthFactor < minimumHealthFactor) revert BorrowAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay the base token to a comet.
     */
    function repayBase(IComet comet, uint256 assets) external {
        _verifyComet(comet);

        ERC20 base = comet.baseToken();

        assets = _maxAvailable(base, assets);

        uint256 borrowedAssets = comet.borrowBalanceOf(address(this));

        if (assets > borrowedAssets) assets = borrowedAssets;

        base.safeApprove(address(comet), assets);

        comet.supply(address(base), assets);

        _revokeExternalApproval(base, address(comet));
    }

    /**
     * @notice Reverts if a Cellar is not setup to interact with a given Comet.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     * @dev This function is never triggered during a Cellar setup in constructor so we do not need to worry about
     *      the cellar not existing when verifying a comet.
     */
    function _verifyComet(IComet comet) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(comet)));
        Cellar cellar = Cellar(address(this));
        Registry registry = cellar.registry();
        uint32 positionId = registry.getPositionHashToPositionId(positionHash);
        if (!cellar.isPositionUsed(positionId)) revert BorrowAdaptor___InvalidComet(address(comet));
    }
}
