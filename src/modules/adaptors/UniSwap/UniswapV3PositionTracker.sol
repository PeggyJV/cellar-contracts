// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/modules/adaptors/BaseAdaptor.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Uniswap V3 Position Tracker
 * @notice Tracks Uniswap V3 positions Cellars have entered.
 * @author crispymangoes
 */
contract UniswapV3PositionTracker {
    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice The max possible amount of LP positions a caller can hold for each token0 and token1 pair.
     */
    uint256 public constant MAX_HOLDINGS = 20;

    /**
     * @notice Mapping used to keep track of what LP positions a caller is currently holding.
     * @dev Split up by the LPs underlying token0 and token1.
     */
    mapping(address => mapping(ERC20 => mapping(ERC20 => uint256[]))) private callerToToken0ToToken1ToHoldings;

    //============================== ERRORS ===============================

    error UniswapV3PositionTracker__MaxHoldingsExceeded();
    error UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
    error UniswapV3PositionTracker__CallerOwnsTokenId();
    error UniswapV3PositionTracker__TokenIdAlreadyTracked();
    error UniswapV3PositionTracker__TokenIdMustBeOwnedByDeadAddress();
    error UniswapV3PositionTracker__TokenIdNotFound();

    //============================== IMMUTABLES ===============================

    /**
     * @notice Uniswap V3 Position Manager.
     */
    INonfungiblePositionManager public immutable positionManager;

    constructor(INonfungiblePositionManager _positionManager) {
        positionManager = _positionManager;
    }

    //============================== External Mutative Functions ===============================

    /**
     * @notice Add a tokenId to the callers holdings.
     * @dev Caller must OWN the token id
     * @dev Caller must have enough room in holdings
     * @dev Token id must be UNIQUE for the given token0 and token1.
     */
    function addPositionToArray(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[msg.sender][token0][token1].length;

        if (holdingLength >= MAX_HOLDINGS) revert UniswapV3PositionTracker__MaxHoldingsExceeded();
        // Make sure the position is not already in the array
        (bool found, ) = checkIfPositionIsInTracker(msg.sender, tokenId, token0, token1);
        if (found) revert UniswapV3PositionTracker__TokenIdAlreadyTracked();

        callerToToken0ToToken1ToHoldings[msg.sender][token0][token1].push(tokenId);
    }

    /**
     * @notice Remove a tokenId from the callers holdings, and burn it.
     * @dev Token id must actually be in given holdings.
     * @dev Caller must approve this contract to spend its token id.
     * @dev `burn` checks if given token as any liquidity or fees and reverts if so.
     */
    function removePositionFromArray(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        _iterateArrayAndPopTarget(msg.sender, tokenId, token0, token1);

        // Prove caller not only owns this token, but also that they approved this contract to spend it.
        positionManager.transferFrom(msg.sender, address(this), tokenId);

        // Burn this tokenId. Checks if token has liquidity or fees in it.
        positionManager.burn(tokenId);
    }

    /**
     * @notice If a caller manages to add a token id to holdings, but no longer owns it, this function
     *         can be used to remove it from holdings.
     * @dev Caller can not own given token id.
     * @dev Token id must be callers holdings.
     */
    function removePositionFromArrayThatIsNotOwnedByCaller(uint256 tokenId, ERC20 token0, ERC20 token1) external {
        if (positionManager.ownerOf(tokenId) == msg.sender) revert UniswapV3PositionTracker__CallerOwnsTokenId();

        _iterateArrayAndPopTarget(msg.sender, tokenId, token0, token1);
    }

    //============================== View Functions ===============================

    /**
     * @notice Returns a bool if `tokenId` is found in callers token0 and token1 holdings,
     *         as well as the index it was found.
     *         If not found returns false and 0 for index.
     */
    function checkIfPositionIsInTracker(
        address caller,
        uint256 tokenId,
        ERC20 token0,
        ERC20 token1
    ) public view returns (bool positionFound, uint256 index) {
        // Search through caller's holdings and return true if the token id was found.
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[caller][token0][token1].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentTokenId = callerToToken0ToToken1ToHoldings[caller][token0][token1][i];
            if (currentTokenId == tokenId) {
                return (true, i);
            }
        }

        // If we made it this far the LP position was not found.
        return (false, 0);
    }

    /**
     * @notice Return an array of tokens a caller owns for a given token0 and token1.
     */
    function getTokens(address caller, ERC20 token0, ERC20 token1) external view returns (uint256[] memory tokens) {
        return callerToToken0ToToken1ToHoldings[caller][token0][token1];
    }

    //============================== Internal View Functions ===============================

    /**
     * @notice Iterates over a user holdings, and removes targetId if found.
     * @dev If not found, revert.
     */
    function _iterateArrayAndPopTarget(address user, uint256 targetId, ERC20 token0, ERC20 token1) internal {
        uint256 holdingLength = callerToToken0ToToken1ToHoldings[user][token0][token1].length;

        for (uint256 i; i < holdingLength; ++i) {
            uint256 currentTokenId = callerToToken0ToToken1ToHoldings[user][token0][token1][i];
            if (currentTokenId == targetId) {
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
}
