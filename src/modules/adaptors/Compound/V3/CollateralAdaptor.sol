// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";
import { V3Helper } from "src/modules/adaptors/Compound/V3/V3Helper.sol";

/**
 * @title Compound CToken Adaptor
 * @notice Allows Cellars to interact with Compound CToken positions.
 * @author crispymangoes
 */
contract CollateralAdaptor is BaseAdaptor, V3Helper {
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

    error CollateralAdaptor__HealthFactorTooLow();

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
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
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Collateral Adaptor V 1.0"));
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
     * @notice Identical to `balanceOf`, unless isLiquid configuration data is false, then returns 0.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of comet base token.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (IComet comet, ERC20 collateralAsset) = abi.decode(adaptorData, (IComet, ERC20));
        (uint128 collateral, ) = comet.userCollateral(msg.sender, address(collateralAsset));
        return collateral;
    }

    /**
     * @notice Returns `comet.baseToken()`
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

    function supplyCollateral(IComet comet, ERC20 collateralAsset, uint256 assets) external {
        // TODO verify comet, and collateralAsset
        assets = _maxAvailable(collateralAsset, assets);
        collateralAsset.safeApprove(address(comet), assets);

        comet.supply(address(collateralAsset), assets);

        _revokeExternalApproval(collateralAsset, address(comet));
    }

    function withdrawCollateral(IComet comet, ERC20 collateralAsset, uint256 assets) external {
        // TODO verify comet, and collateralAsset

        // TODO what about reserves?
        (uint256 collateralBalance, ) = comet.userCollateral(address(this), address(collateralAsset));
        if (assets > collateralBalance) assets = collateralBalance;

        comet.withdraw(address(collateralAsset), assets);

        uint256 healthFactor = getAccountHealthFactor(comet, address(this));
        if (healthFactor < minimumHealthFactor) revert CollateralAdaptor__HealthFactorTooLow();
    }
}
