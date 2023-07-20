// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/modules/adaptors/BaseAdaptor.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Uniswap V3 Position Tracker
 * @notice Tracks Uniswap V3 positions Cellars have entered.
 * @author crispymangoes
 */
contract SinglePositionUniswapV3PositionTracker {
    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Mapping used to keep track of one LP position a caller is currently holding.
     */
    mapping(address => mapping(address => mapping(uint256 => uint256))) private callerToPoolToIndexToPositionId;

    //============================== ERRORS ===============================

    error UniswapV3PositionTracker__CallerDoesNotOwnTokenId();
    error UniswapV3PositionTracker__CallerOwnsTokenId();
    error UniswapV3PositionTracker__IndexAlreadyUsed();
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
    function addPositionToTracker(uint256 tokenId, address pool, uint256 index) external {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert UniswapV3PositionTracker__CallerDoesNotOwnTokenId();

        if (callerToPoolToIndexToPositionId[msg.sender][pool][index] != 0)
            revert UniswapV3PositionTracker__IndexAlreadyUsed();

        callerToPoolToIndexToPositionId[msg.sender][pool][index] = tokenId;
    }

    /**
     * @notice Remove a tokenId from the callers holdings, and burn it.
     * @dev Token id must actually be in given holdings.
     * @dev Caller must approve this contract to spend its token id.
     * @dev `burn` checks if given token as any liquidity or fees and reverts if so.
     */
    function removePositionFromTracker(address pool, uint256 index) external returns (uint256 tokenId) {
        tokenId = callerToPoolToIndexToPositionId[msg.sender][pool][index];

        if (tokenId == 0) revert UniswapV3PositionTracker__TokenIdNotFound();

        delete callerToPoolToIndexToPositionId[msg.sender][pool][index];

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
    function removePositionThatIsNotOwnedByCaller(address pool, uint256 index) external {
        uint256 tokenId = callerToPoolToIndexToPositionId[msg.sender][pool][index];
        if (positionManager.ownerOf(tokenId) == msg.sender) revert UniswapV3PositionTracker__CallerOwnsTokenId();

        delete callerToPoolToIndexToPositionId[msg.sender][pool][index];
    }

    //============================== View Functions ===============================

    /**
     * @notice Return an array of tokens a caller owns for a given token0 and token1.
     */
    function getCallerTokenAtIndex(address pool, uint256 index) external view returns (uint256) {
        return callerToPoolToIndexToPositionId[msg.sender][pool][index];
    }

    function getTokenAtIndex(address user, address pool, uint256 index) external view returns (uint256) {
        return callerToPoolToIndexToPositionId[user][pool][index];
    }
}
