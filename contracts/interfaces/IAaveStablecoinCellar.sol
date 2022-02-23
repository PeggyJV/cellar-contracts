// SPDX-License-Identifier: Apache-2.0
// VolumeFi Software, Inc.

pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title interface for AaveStablecoinCellar
interface IAaveStablecoinCellar is IERC20 {
    /**
     * @notice Emitted when liquidity is increased for cellar
     * @param input_token the address of the token
     * @param user the address of the user
     * @param amount the amount of the token
     * @param timestamp the timestamp of the action
     **/
    event AddedLiquidity(
        address indexed input_token,
        address user,
        uint256 amount,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when tokens swapped
     * @param tokenIn the address of the tokenIn
     * @param amountIn the amount of the tokenIn
     * @param tokenOut the address of the tokenOut
     * @param amountOut the amount of the tokenOut
     * @param timestamp the timestamp of the action
     **/
    event Swapped(
        address indexed tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOut,
        uint256 timestamp
    );
    
    /**
    * @dev emitted on deposit to Aave
    * @param token the address of the token
    * @param token_amount the amount to be deposited
    * @param timestamp the timestamp of the action
    **/
    event DepositeToAave(
        address indexed token,
        uint256 token_amount,
        uint256 timestamp
    );
    
    /**
    * @dev emitted on redeem from Aave
    * @param token the address of the token
    * @param token_amount the amount to be redeemed
    * @param timestamp the timestamp of the action
    **/
    event RedeemFromAave(
        address indexed token,
        uint256 token_amount,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when transfer ownership
     * @param newOwner new owner address
     **/
    event TransferOwnership (
        address newOwner
    );
    
    error NonSupportedToken();
    error PathIsTooShort();
    error UserNotHaveEnoughBalance();
    error TokenAlreadyInitialized();
    error ZeroAmount();
    
    error TokenIsNotSupportedByAave();
    error NotEnoughTokenLiquidity();
    error InsufficientAaveDepositBalance();
    
    error NonPermission();
    error Reentrance();
    error InvalidInput();
    error TransferToZeroAddress();
    error TransferFromZeroAddress();
    error MintToZeroAddress();
    error BurnFromZeroAddress();
    error ApproveToZeroAddress();
    error ApproveFromZeroAddress();

    /// @notice transfer ownership to new address
    /// @param newOwner address of new owner
    function transferOwnership(address newOwner) external;

    /**
     * @dev Returns owner address
     */
    function owner() external view returns (address);

    /**
     * @dev Returns name of the token as ERC20
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns symbol of the token as ERC20
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns decimals of the token as ERC20
     */
    function decimals() external pure returns (uint8);
}


