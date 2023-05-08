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

// @title ILiquidityGaugev3Custom
// @notice custom interface created to work with v3 LiquidityGauges from Balancer/Curve
// @author 0xEinCodes
interface ILiquidityGaugev3Custom {
    /**
     * @notice Returns true if `gauge` was created by this factory.
     */
    function claim_rewards(address _addr, address _receiver) external;

    function claimable_reward(address _user, address _reward_token) external returns(uint256);
    
    function claimable_tokens(address _addr) external returns(uint256);

    /// For depositing and withdrawing BPTs for respective liquidityGauge

    function deposit(uint256 amount, address receiver) external;

    function withdraw(uint256 amount) external;


}
