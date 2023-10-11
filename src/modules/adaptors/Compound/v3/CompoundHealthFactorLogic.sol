// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16; // TODO: update to 0.8.21

import { Math } from "src/utils/Math.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";

/**
 * @title CompoundV3 Health Factor Logic contract.
 * @notice Implements health factor logic used by both
 *         the CompoundV3SupplyAdaptor && CompoundV3DebtAdaptor.
 * @author crispymangoes, 0xEinCodes
 * NOTE: helper functions made virtual in case future versions require different implementation logic. The logic here is written in compliance with CompoundV3
 */
contract CompoundHealthFactorLogic {
    using Math for uint256;

    /**
     * @notice Get current collateral balance for caller in specified CompMarket and Collateral Asset.
     * @dev Queries the `CometStorage.sol` nested mapping for struct UserCollateral.
     * @param _fraxlendPair The specified Fraxlend Pair
     * @param _user The specified user
     * @return collateralBalance of user in fraxlend pair
     */
    function _userCollateralBalance(
        CometInterface _compMarket,
        address _asset
    ) internal view virtual returns (uint256 collateralBalance) {
        UserCollateral userCollateral = _compMarket.userCollateral(address(_compMarket), _asset);
        return userCollateral.balance;
    }
}
