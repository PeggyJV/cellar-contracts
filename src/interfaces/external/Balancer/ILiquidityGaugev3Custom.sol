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
// built this wrt to example gauges obtained via:
// 1. Going to ILiquidityGaugeFactory from the docs
// 2. Calling `getPoolGauge()` to obtain address of associated gauge (https://etherscan.io/address/0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC#readContract)
// 3. Looking into the actual vyper code of the gauge (ex. OHM/wETH (https://etherscan.io/address/0xd1ec5e215e8148d76f4460e4097fd3d5ae0a3558) gauge --> https://etherscan.io/address/0x5f2c3422a675860f0e019Ddd78C6fA681bE84bd4#readContract) TODO: - NOTE: some gauges seem to repore address(0) when using the `getPoolGauge()` function from Balancer which makes me think that certain gauges came from different versions of the gaugeFactory. This may bring up problems if there are old gauges out there that we want to interact with. For investigation: See convo w/ mkFlow where I confirmed that the specific gauges I was looking at were variations of curve's, which I found corroborating info on it via governance forums for veBal. <Link>
interface ILiquidityGaugev3Custom {
    /**
     * @notice Returns true if `gauge` was created by this factory.
     * NOTE: write function
     */
    function claim_rewards(address _addr, address _receiver) external;

    // view function
    function claimable_reward(address _user, address _reward_token) external returns(uint256);
    
    // write function
    function claimable_tokens(address _addr) external returns(uint256);

    /// For depositing and withdrawing BPTs for respective liquidityGauge

    // write function
    function deposit(uint256 amount, address receiver) external;

    // write function
    function withdraw(uint256 amount) external;

}
