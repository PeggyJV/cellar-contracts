// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IPool } from "src/interfaces/external/IPool.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";

/**
 * @title Enable Asset As Collateral Adaptor
 * @notice Allows Cellars to adjust whether Aave V2
 *         assets are used as collateral or not.
 * @author crispymangoes
 */
contract AaveV2EnableAssetAsCollateralAdaptor is PositionlessAdaptor {
    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    /**
     @notice Attempted use asset as collateral to false would lower Cellar health factor too low.
     */
    error AaveV2EnableAssetAsCollateralAdaptor__HealthFactorTooLow();

    /**
     * @notice The Aave V3 Pool contract on current network.
     * @dev For mainnet use 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.
     */
    IPool public immutable pool;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address v2Pool, uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        pool = IPool(v2Pool);
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
        return keccak256(abi.encode("Aave V2 Enable Asset As Collateral Adaptor V 0.1"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows a strategist to choose to use an asset as collateral or not.
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
        pool.setUserUseReserveAsCollateral(asset, useAsCollateral);

        // If useAsCollateral is false then run a health factor check.
        if (!useAsCollateral) {
            (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
            if (healthFactor < minimumHealthFactor) revert AaveV2EnableAssetAsCollateralAdaptor__HealthFactorTooLow();
        }
    }
}
