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

    uint256 public constant MAX_HOLDINGS = 20;

    mapping(address => mapping(ERC20 => mapping(ERC20 => uint256[]))) private callerToToken0ToToken1ToHoldings;

    error UniswapV3PositionTracker__MaxHoldingsExceeded();
    error UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
    error UniswapV3PositionTracker__CallerOwnsTokenId();
    error UniswapV3PositionTracker__TokenIdAlreadyTracked();
    error UniswapV3PositionTracker__TokenIdMustBeOwnedByDeadAddress();
    error UniswapV3PositionTracker__TokenIdNotFound();

    constructor(INonfungiblePositionManager _positionManager) {
        positionManager = _positionManager;
    }

    function addPositionToArray(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[msg.sender][token0][token1].length;

        if (holdingLength >= MAX_HOLDINGS) revert UniswapV3PositionTracker__MaxHoldingsExceeded();
        // Make sure the position is not already in the array
        (bool found, ) = checkIfPositionIsInTracker(msg.sender, tokenId, token0, token1);
        if (found) revert UniswapV3PositionTracker__TokenIdAlreadyTracked();

        callerToToken0ToToken1ToHoldings[msg.sender][token0][token1].push(tokenId);
    }

    function removePositionFromArray(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        // Prove caller not only owns this token, but also that they approved this contract to spend it.
        positionManager.transferFrom(msg.sender, address(this), tokenId);

        // Burn this tokenId. Checks if token has liquidity or fees in it.
        positionManager.burn(tokenId);

        _iterateArrayAndPopTarget(msg.sender, tokenId, token0, token1);
    }

    function removePositionFromArrayThatIsNotOwnedByCaller(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        if (positionManager.ownerOf(tokenId) == msg.sender) revert UniswapV3PositionTracker__CallerOwnsTokenId();

        _iterateArrayAndPopTarget(msg.sender, tokenId, token0, token1);
    }

    function _iterateArrayAndPopTarget(address user, uint256 targetId, ERC20 token0, ERC20 token1) internal {
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[user][token0][token1].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerToToken0ToToken1ToHoldings[user][token0][token1][i];
            if (currentPositionId == targetId) {
                // We found the target tokenId.
                callerToToken0ToToken1ToHoldings[user][token0][token1][i] = callerToToken0ToToken1ToHoldings[user][
                    token0
                ][token1][holdingLength - 1];
                callerToToken0ToToken1ToHoldings[user][token0][token1].pop();
                return;
            }
        }

        // If we made it this far we did not find the tokenId in the array, so revert.
        revert UniswapV3PositionTracker__TokenIdNotFound();
    }

    function checkIfPositionIsInTracker(
        address caller,
        uint256 positionId,
        ERC20 token0,
        ERC20 token1
    ) public view returns (bool positionFound, uint256 index) {
        // Search through caller's holdings and return true if the position was found.
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[msg.sender][token0][token1].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentPositionId = callerToToken0ToToken1ToHoldings[caller][token0][token1][i];
            if (currentPositionId == positionId) {
                return (true, i);
            }
        }

        // If we made it this far the LP position was not found.
        return (false, 0);
    }

    function getPositions(
        address caller,
        ERC20 token0,
        ERC20 token1
    ) external view returns (uint256[] memory positions) {
        return callerToToken0ToToken1ToHoldings[caller][token0][token1];
    }
}
