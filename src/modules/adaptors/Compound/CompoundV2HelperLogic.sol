// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title CompoundV2 Helper Logic contract.
 * @notice Implements health factor logic used by both
 *         the CTokenAdaptorV2 && CompoundV2DebtAdaptor, and provides Market struct.
 * @author crispymangoes, 0xEinCodes
 * NOTE: helper functions made virtual in case future Fraxlend Pair versions require different implementation logic.
 */
contract CompoundV2HelperLogic {
    using Math for uint256;

    // From Compotroller
    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;
        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        /// @notice Whether or not this market receives COMP
        bool isComped;
    }

    /**
     * @notice The ```_getHealthFactor``` function returns the current health factor
     * TODO:
     */
    function _getHealthFactor() public {}
}
