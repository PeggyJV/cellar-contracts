// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math, Cellar, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";
import { CompoundV3Helper } from "src/modules/adaptors/Compound/V3/CompoundV3Helper.sol";

/**
 * @title Compound V3 Collateral Adaptor
 * @notice Allows Cellars to interact with collateral on Compound V3.
 * @author crispymangoes
 */
contract CompoundV3CollateralAdaptor is BaseAdaptor, CompoundV3Helper {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Comet comet, ERC20 collateralAsset)
    // Where:
    // `comet` is the underling Compound V3 Comet this adaptor is working with
    // `collateralAsset` is the CompoundV3 asset to use as collateral.
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted action would lower health factor below adaptor minimum.
     */
    error CollateralAdaptor__HealthFactorTooLow();

    /**
     * @notice Attempted to use an invalid comet and/or collateral asset.
     */
    error CollateralAdaptor___InvalidCometOrCollateral(address comet, address collateral);

    /**
     * @notice Minimum Health Factor enforced after every collateral withdraw.
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
        return keccak256(abi.encode("Compound V3 Collateral Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Deposit collateral asset to Compound V3.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (IComet comet, ERC20 collateralAsset) = abi.decode(adaptorData, (IComet, ERC20));
        _verifyCometAndCollateral(comet, collateralAsset);

        collateralAsset.safeApprove(address(comet), assets);

        comet.supply(address(collateralAsset), assets);

        _revokeExternalApproval(collateralAsset, address(comet));
    }

    /**
     * @notice Not supported.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice Reports 0, as collateral withdraws lower the health factor of the cellar.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of collateral in Compound V3.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IComet comet, ERC20 collateralAsset) = abi.decode(adaptorData, (IComet, ERC20));
        uint128 collateral = comet.collateralBalanceOf(msg.sender, address(collateralAsset));
        return collateral;
    }

    /**
     * @notice Returns the collateral asset used in Compound V3.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        (, ERC20 collateralAsset) = abi.decode(adaptorData, (IComet, ERC20));
        return collateralAsset;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to add collateral to Compound V3.
     */
    function supplyCollateral(IComet comet, ERC20 collateralAsset, uint256 assets) external {
        _verifyCometAndCollateral(comet, collateralAsset);

        assets = _maxAvailable(collateralAsset, assets);
        collateralAsset.safeApprove(address(comet), assets);

        comet.supply(address(collateralAsset), assets);

        _revokeExternalApproval(collateralAsset, address(comet));
    }

    /**
     * @notice Allows strategists to remove collateral from Compound V3.
     * @dev Enforces a minimum health factor check after withdrawal.
     */
    function withdrawCollateral(IComet comet, ERC20 collateralAsset, uint256 assets) external {
        _verifyCometAndCollateral(comet, collateralAsset);

        if (assets == type(uint256).max) {
            uint256 collateralBalance = comet.collateralBalanceOf(address(this), address(collateralAsset));
            assets = collateralBalance;
        }

        comet.withdraw(address(collateralAsset), assets);

        uint256 healthFactor = getAccountHealthFactor(comet, address(this));
        if (healthFactor < minimumHealthFactor) revert CollateralAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Reverts if a Cellar is not setup to interact with a given Comet, and collateral.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     * @dev This function is never triggered during a Cellar setup in constructor so we do not need to worry about
     *      the cellar not existing when verifying a comet.
     */
    function _verifyCometAndCollateral(IComet comet, ERC20 collateralAsset) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(comet, collateralAsset)));
        Cellar cellar = Cellar(address(this));
        Registry registry = cellar.registry();
        uint32 positionId = registry.getPositionHashToPositionId(positionHash);
        if (!cellar.isPositionUsed(positionId))
            revert CollateralAdaptor___InvalidCometOrCollateral(address(comet), address(collateralAsset));
    }
}
