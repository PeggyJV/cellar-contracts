// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UniswapV3LiquidityManager {
    struct Position {
        address token0; // Token pricing in returned in.
        address token1;
    }

    /// @dev cellar adaptors would know the position Id.

    mapping(uint256 => Position) public idToPosition;
    mapping(uint256 => mapping(address => uint256)) public userPosition; // Maps position Id -> user address -> Token Id

    // Allows owner to add new position Ids
    function addNewPosition(address _token0, address _token1) external {
        uint256 id = uint256(keccak256(abi.encodePacked(_token0, _token1)));
        // Make sure ID is not already set up
        idToPosition[id] = Position({ token0: _token0, token1: _token1 });
    }

    function assetOf(uint256 positionId) external view returns (ERC20) {
        return ERC20(idToPosition[positionId].token0);
    }

    //TODO this set up means cellars could only have 1 position for each position id
    function balanceOfUnderlying(address user, uint256 positionId) public {}
}
