// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { IMorphoV3 } from "src/interfaces/external/Morpho/IMorphoV3.sol";

/**
 * @title Morpho Aave V3 Health Factor Logic contract.
 * @notice Implements health factor logic used by both
 *         the Morpho Aave V3 A Token and debt Token adaptors.
 * @author crispymangoes
 */
contract MorphoAaveV3HealthFactorLogic {
    using Math for uint256;

    /**
     * @notice Code pulled directly from Morpho Position Maanager.
     * https://etherscan.io/address/0x4592e45e0c5DbEe94a135720cCfF2e4353dAc6De#code
     */
    function _getUserHealthFactor(IMorphoV3 morpho, address user) internal view returns (uint256) {
        IMorphoV3.LiquidityData memory liquidityData = morpho.liquidityData(user);

        return
            liquidityData.debt > 0
                ? uint256(1e18).mulDivDown(liquidityData.maxDebt, liquidityData.debt)
                : type(uint256).max;
    }
}
