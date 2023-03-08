// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Uniswap V3 Adaptor
 * @notice Allows Cellars to hold and interact with Uniswap V3 LP Positions.
 * @dev `balanceOf` credited to https://github.com/0xparashar/UniV3NFTOracle/blob/master/contracts/UniV3NFTOracle.sol
 * @author crispymangoes
 */
contract UniswapV3PositionTracker {
    using SafeTransferLib for ERC20;

    INonfungiblePositionManager public immutable positionManager;

    uint256 public constant MAX_HOLDINGS = 100;

    mapping(address => uint256[]) private callerLPHoldings;

    constructor(INonfungiblePositionManager _positionManager) {
        positionManager = _positionManager;
    }

    function addPositionToArray(uint256 tokenId) external {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert("Caller does not own tokenId.");
        uint256 holdingLength = callerLPHoldings[msg.sender].length;

        if (holdingLength >= MAX_HOLDINGS) revert("Too big");
        // Make sure the position is not already in the array
        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerLPHoldings[msg.sender][i];
            if (currentPositionId == tokenId) revert("Position already in array");
        }

        callerLPHoldings[msg.sender].push(tokenId);
    }

    // TODO should this check if the caller has the token or does not have the token
    // ie are we asking them to burn the token before or after this is called
    function removePositionFromArray(uint256 tokenId) external {
        if (positionManager.ownerOf(tokenId) != address(1)) revert("Token Id must be owened by DEAD address.");

        uint256 holdingLength = callerLPHoldings[msg.sender].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerLPHoldings[msg.sender][i];
            if (currentPositionId == tokenId) {
                // We found the target tokenId.
                callerLPHoldings[msg.sender][i] = callerLPHoldings[msg.sender][holdingLength - 1];
                delete callerLPHoldings[msg.sender][holdingLength - 1];
                return;
            }
        }

        // If we made it this far we did not find the tokenId in the array, so revert.
        revert("Token Id not found");
    }

    // TODO function that returns if a token is in the array or not.

    function checkIfPositionIsInTracker(
        address caller,
        uint256 positionId
    ) external view returns (bool positionFound, uint256 index) {
        // Search through caller's holdings and return true if the position was found.
        uint256 holdingLength = callerLPHoldings[msg.sender].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerLPHoldings[caller][i];
            if (currentPositionId == positionId) {
                return (true, i);
            } else if (currentPositionId == 0) return (false, 0);
        }

        // If we made it this far the LP position was not found.
        return (false, 0);
    }

    function getPositions(address caller) external view returns (uint256[] memory positions) {
        return callerLPHoldings[caller];
    }

    // struct PositionUnderlying {
    //     uint256 tokenId;
    //     uint256 amount0;
    //     uint256 amount1;
    // }

    // function viewPositionsUnderlying(address owner) external view returns (PositionUnderlying[20] memory summary) {}
}
