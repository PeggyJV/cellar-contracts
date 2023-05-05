// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

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

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Aave V2 Enable Asset As Collateral Adaptor V 0.0"));
    }

    /**
     * @notice The Aave V2 Pool contract on current network.
     */
    function pool() internal view returns (IPool) {
        uint256 chainId = block.chainid;
        if (chainId == ETHEREUM) return IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        revert BaseAdaptor__ChainNotSupported(chainId);
    }

    /**
     * @notice Minimum Health Factor enforced when useAsCollateral is set to false.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.05e18;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows a strategist to choose to use an asset as collateral or not.
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
        pool().setUserUseReserveAsCollateral(asset, useAsCollateral);

        // If useAsCollateral is false then run a health factor check.
        if (!useAsCollateral) {
            (, , , , , uint256 healthFactor) = pool().getUserAccountData(address(this));
            if (healthFactor < HFMIN()) revert AaveV2EnableAssetAsCollateralAdaptor__HealthFactorTooLow();
        }
    }
}
