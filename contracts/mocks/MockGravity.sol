// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockGravity {
    using SafeERC20 for IERC20;
    error InvalidSendToCosmos();

    function sendToCosmos(address _tokenContract, bytes32, uint256 _amount) external {
        // we snapshot our current balance of this token
        uint256 ourStartingBalance = IERC20(_tokenContract).balanceOf(address(this));

        // attempt to transfer the user specified amount
        IERC20(_tokenContract).safeTransferFrom(msg.sender, address(this), _amount);

        // check what this particular ERC20 implementation actually gave us, since it doesn't
        // have to be at all related to the _amount
        uint256 ourEndingBalance = IERC20(_tokenContract).balanceOf(address(this));

        // a very strange ERC20 may trigger this condition, if we didn't have this we would
        // underflow, so it's mostly just an error message printer
        if (ourEndingBalance <= ourStartingBalance) {
            revert InvalidSendToCosmos();
        }
    }
}