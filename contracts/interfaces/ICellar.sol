// SPDX-License-Identifier: Apache-2.0
// VolumeFi Software, Inc.

pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title interface for Cellar
interface ICellar is IERC20 {
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
     * @param _token0 the address of the _token0
     * @param amountIn the amount of the _token0
     * @param _token1 the address of the _token1
     * @param amountOut the amount of the _token1
     * @param timestamp the timestamp of the action
     **/
    event Swapped(
        address indexed _token0,
        uint256 amountIn,
        address _token1,
        uint256 amountOut,
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
    error userNotHaveEnoughBalance();
    
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


