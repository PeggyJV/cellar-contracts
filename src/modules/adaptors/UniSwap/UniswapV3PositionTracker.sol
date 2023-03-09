// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Uniswap V3 Position Tracker
 * @notice Tracks Uniswap V3 positions Cellars have entered.
 * @author crispymangoes
 */
contract UniswapV3PositionTracker {
    using SafeTransferLib for ERC20;

    INonfungiblePositionManager public immutable positionManager;

    uint256 public constant MAX_HOLDINGS = 100;

    mapping(address => uint256[]) private callerLPHoldings;

    error UniswapV3PositionTracker__MaxHoldingsExceeded();
    error UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
    error UniswapV3PositionTracker__TokenIdAlreadyTracked();
    error UniswapV3PositionTracker__TokenIdMustBeOwnedByDeadAddress();
    error UniswapV3PositionTracker__TokenIdNotFound();

    constructor(INonfungiblePositionManager _positionManager) {
        positionManager = _positionManager;
    }

    function addPositionToArray(uint256 tokenId) external {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
        uint256 holdingLength = callerLPHoldings[msg.sender].length;

        if (holdingLength >= MAX_HOLDINGS) revert UniswapV3PositionTracker__MaxHoldingsExceeded();
        // Make sure the position is not already in the array
        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerLPHoldings[msg.sender][i];
            if (currentPositionId == tokenId) revert UniswapV3PositionTracker__TokenIdAlreadyTracked();
        }

        callerLPHoldings[msg.sender].push(tokenId);
    }

    function removePositionFromArray(uint256 tokenId) external {
        if (positionManager.ownerOf(tokenId) != address(1))
            revert UniswapV3PositionTracker__TokenIdMustBeOwnedByDeadAddress();

        uint256 holdingLength = callerLPHoldings[msg.sender].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerLPHoldings[msg.sender][i];
            if (currentPositionId == tokenId) {
                // We found the target tokenId.
                callerLPHoldings[msg.sender][i] = callerLPHoldings[msg.sender][holdingLength - 1];
                callerLPHoldings[msg.sender].pop();
                // delete callerLPHoldings[msg.sender][holdingLength - 1];
                return;
            }
        }

        // If we made it this far we did not find the tokenId in the array, so revert.
        revert UniswapV3PositionTracker__TokenIdNotFound();
    }

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
}
