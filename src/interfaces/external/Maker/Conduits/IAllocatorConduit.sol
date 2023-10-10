// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.8.0;

/**
 *  @title IAllocatorConduit
 *  @dev   Conduits are to be used to manage investment positions for multiple Allocators.
 */
interface IAllocatorConduit {
    /**
     *  @dev   Event emitted when a deposit is made to the Conduit.
     *  @param ilk    The unique identifier of the ilk.
     *  @param asset  The address of the asset deposited.
     *  @param origin The address where the asset is coming from.
     *  @param amount The amount of asset deposited.
     */
    event Deposit(bytes32 indexed ilk, address indexed asset, address origin, uint256 amount);

    /**
     *  @dev   Event emitted when a withdrawal is made from the Conduit.
     *  @param ilk         The unique identifier of the ilk.
     *  @param asset       The address of the asset withdrawn.
     *  @param destination The address where the asset is sent.
     *  @param amount      The amount of asset withdrawn.
     */
    event Withdraw(bytes32 indexed ilk, address indexed asset, address destination, uint256 amount);

    /**
     *  @dev   Function for depositing tokens into a Fund Manager.
     *  @param ilk    The unique identifier of the ilk.
     *  @param asset  The asset to deposit.
     *  @param amount The amount of tokens to deposit.
     */
    function deposit(bytes32 ilk, address asset, uint256 amount) external;

    /**
     *  @dev   Function for withdrawing tokens from a Fund Manager.
     *  @param  ilk         The unique identifier of the ilk.
     *  @param  asset       The asset to withdraw.
     *  @param  maxAmount   The max amount of tokens to withdraw. Setting to "type(uint256).max" will ensure to withdraw all available liquidity.
     *  @return amount      The amount of tokens withdrawn.
     */
    function withdraw(bytes32 ilk, address asset, uint256 maxAmount) external returns (uint256 amount);

    /**
     *  @dev    Function to get the maximum deposit possible for a specific asset and ilk.
     *  @param  ilk         The unique identifier of the ilk.
     *  @param  asset       The asset to check.
     *  @return maxDeposit_ The maximum possible deposit for the asset.
     */
    function maxDeposit(bytes32 ilk, address asset) external view returns (uint256 maxDeposit_);

    /**
     *  @dev    Function to get the maximum withdrawal possible for a specific asset and ilk.
     *  @param  ilk          The unique identifier of the ilk.
     *  @param  asset        The asset to check.
     *  @return maxWithdraw_ The maximum possible withdrawal for the asset.
     */
    function maxWithdraw(bytes32 ilk, address asset) external view returns (uint256 maxWithdraw_);

}
