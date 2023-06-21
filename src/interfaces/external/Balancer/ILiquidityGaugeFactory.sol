// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./ILiquidityGauge.sol";
import "./ILiquidityGaugev3Custom.sol";

interface ILiquidityGaugeFactory {
    /**
     * @notice Checks if gauge was created from this factory contract
     * @return bool where true indicates `gauge` was created by this factory.
     */
    function isGaugeFromFactory(address gauge) external view returns (bool);

    /**
     * @notice Returns the address of the gauge belonging to `pool`.
     * NOTE: Function call getPoolGauge(address) is not in the original ILiquidityGaugeFactory
     * @return ILiquidityGauge(_poolGauge[pool]
     */
    function getPoolGauge(address pool) external view returns (ILiquidityGaugev3Custom);
}
