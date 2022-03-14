// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import "./interfaces/IAaveStablecoinCellar.sol";
import "./interfaces/IAaveProtocolDataProvider.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ILendingPool.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Sommelier AaveStablecoinCellar contract
 * @notice AaveStablecoinCellar contract for Sommelier Network
 * @author Sommelier Finance
 */
contract AaveStablecoinCellar is
    IAaveStablecoinCellar,
    ERC20,
    ReentrancyGuard,
    Ownable
{
    using SafeTransferLib for ERC20;

    // Uniswap Router V3 contract address
    address private immutable swapRouter; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    // Aave Lending Pool V2 contract
    ILendingPool public immutable aaveLendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    
    // Aave Protocol Data Provider V2 contract
    IAaveProtocolDataProvider public immutable aaveDataProvider; // 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d
    
    // Declare the variables and mappings
    address[] public inputTokensList;
    mapping(address => bool) internal inputTokens;

    uint24 public constant POOL_FEE = 3000;
    
    // The address of the token of the current lending position
    address currentLendingToken;

    /**
     * @notice Constructor identifies the name and symbol of the inactive lp token
     * @param _swapRouter Uniswap V3 swap router address
     * @param _aaveLendingPool Aave V2 lending pool address
     * @param _aaveDataProvider Aave Protocol Data Provider V2 contract address
     * @param _name name of inactive LP token
     * @param _symbol symbol of inactive LP token
     */
    constructor(
        address _swapRouter,
        address _aaveLendingPool,
        address _aaveDataProvider,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) Ownable() {
        swapRouter =  _swapRouter;
        aaveLendingPool = ILendingPool(_aaveLendingPool);
        aaveDataProvider = IAaveProtocolDataProvider(_aaveDataProvider);
    }

    /**
     * @dev adds liquidity (the supported token) into the cellar.
     * A corresponding amount of the inactive lp token is minted.
     * @param inputToken the address of the token
     * @param tokenAmount the amount to be added
     **/
    function addLiquidity(address inputToken, uint256 tokenAmount) external {
        if (!inputTokens[inputToken]) revert NonSupportedToken();

        if (tokenAmount == 0) revert ZeroAmount();

        if (ERC20(inputToken).balanceOf(msg.sender) < tokenAmount)
            revert UserNotHaveEnoughBalance();

        ERC20(inputToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        _mint(msg.sender, tokenAmount);

        emit AddedLiquidity(
            inputToken,
            msg.sender,
            tokenAmount,
            block.timestamp
        );
    }

    /**
     * @dev swaps input token by Uniswap V3
     * @param tokenIn the address of the incoming token
     * @param tokenOut the address of the outgoing token
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     **/
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external onlyOwner returns (uint256 amountOut) {
        if (!inputTokens[tokenIn]) revert NonSupportedToken();
        if (!inputTokens[tokenOut]) revert NonSupportedToken();

        // Approve the router to spend tokenIn
        ERC20(tokenIn).safeApprove(swapRouter, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap.
        amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        emit Swapped(tokenIn, amountIn, tokenOut, amountOut, block.timestamp);
    }

    /**
     * @dev swaps tokens by multihop swap in Uniswap V3
     * @param path the token swap path (token addresses)
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     **/
    function multihopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external onlyOwner returns (uint256 amountOut) {
        amountOut = _multihopSwap(
            path,
            amountIn,
            amountOutMinimum
        );
    }
    
    /**
     * @dev internal function that swaps tokens by multihop swap in Uniswap V3
     * @param path the token swap path (token addresses)
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     **/
    function _multihopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        if (path.length < 2) revert PathIsTooShort();
        if (!inputTokens[tokenIn]) revert NonSupportedToken();
        if (!inputTokens[tokenOut]) revert NonSupportedToken();

        // Approve the router to spend first token in path
        ERC20(tokenIn).safeApprove(swapRouter, amountIn);

        bytes memory encodePackedPath = abi.encodePacked(tokenIn);
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(
                encodePackedPath,
                POOL_FEE,
                path[i]
            );
        }

        // Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
        // The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

        // Executes the swap.
        amountOut = ISwapRouter(swapRouter).exactInput(params);

        emit Swapped(tokenIn, amountIn, tokenOut, amountOut, block.timestamp);
    }
    
    /**
     * @dev enters Aave Stablecoin Strategy
     * @param token the address of the token
     * @param tokenAmount the amount of token to be deposited
     **/
    function enterStrategy(address token, uint256 tokenAmount)
        external
        onlyOwner
    {
        // deposits to Aave
        currentLendingToken = token;
        _depositToAave(token, tokenAmount);

        // TODO: to change inactive_lp_shares into active_lp_shares
    }

    /**
     * @dev internal function that deposits cellar holdings into Aave lending pool
     * @param token the address of the token
     * @param tokenAmount the amount of token to be deposited
     **/
    function _depositToAave(address token, uint256 tokenAmount) internal {
        if (!inputTokens[token]) revert NonSupportedToken();
        if (tokenAmount == 0) revert ZeroAmount();

        // verification of liquidity
        if (tokenAmount > ERC20(token).balanceOf(address(this)))
            revert NotEnoughTokenLiquidity();

        ERC20(token).safeApprove(address(aaveLendingPool), tokenAmount);

        // deposit token to Aave protocol
        aaveLendingPool.deposit(token, tokenAmount, address(this), 0);

        emit DepositeToAave(token, tokenAmount, block.timestamp);
    }

    /**
     * @dev redeems an token from Aave protocol
     * @param token the address of the token
     * @param tokenAmount the token amount being redeemed
     * @return withdrawnAmount the withdrawn amount from Aave
     **/
    function redeemFromAave(address token, uint256 tokenAmount)
        public
        onlyOwner
        returns (
            uint256 withdrawnAmount
        )
    {
        if (!inputTokens[token]) revert NonSupportedToken();
        
        uint256 currentATokenBalance = ERC20(currentAToken).balanceOf(address(this));
        
        // withdraw token from Aave protocol
        withdrawnAmount = aaveLendingPool.withdraw(token, tokenAmount, address(this));
          
        emit RedeemFromAave(token, withdrawnAmount, block.timestamp);
    }
    
    /**
     * @dev rebalances of Aave lending position
     * @param newLendingToken the address of the token of the new lending position
     **/
    function rebalance(address newLendingToken, uint256 minNewLendingTokenAmount)
        external
        onlyOwner
    {
        if (currentLendingToken == address(0)) revert NoLendingPosition();
        if (!inputTokens[newLendingToken]) revert NonSupportedToken();

        if(newLendingToken == currentLendingToken) revert SameLendingToken();
        
        uint256 lendingPositionBalance = ERC20(currentAToken).balanceOf(address(this));
        
        lendingPositionBalance = redeemFromAave(currentLendingToken, type(uint256).max);
        
        address[] memory path = new address[](2);
        path[0] = currentLendingToken;
        path[1] = newLendingToken;
        
        uint256 newLendingTokenAmount = _multihopSwap(
            path,
            lendingPositionBalance,
            minNewLendingTokenAmount
        );
        
        _depositToAave(newLendingToken, newLendingTokenAmount);
        currentLendingToken = newLendingToken;
        
        emit Rebalance(newLendingToken, newLendingTokenAmount, block.timestamp);
    }
    
    function initInputToken(address inputToken) public onlyOwner {
        if (inputTokens[inputToken]) revert TokenAlreadyInitialized();

        inputTokens[inputToken] = true;
        inputTokensList.push(inputToken);
    }
}
