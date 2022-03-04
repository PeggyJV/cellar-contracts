// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import "./interfaces/IAaveStablecoinCellar.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
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

    // Aave Lending Pool V2 contract address
    address private immutable aaveLendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Declare the variables and mappings
    address[] public inputTokensList;
    mapping(address => bool) internal inputTokens;

    uint24 public constant POOL_FEE = 3000;

    // Aave deposit balances by tokens
    mapping(address => uint256) public aaveDepositBalances;

    /**
     * @notice Constructor identifies the name and symbol of the inactive lp token
     * @param _swapRouter Uniswap V3 swap router address
     * @param _aaveLendingPool Aave V2 lending pool address
     * @param _name name of inactive LP token
     * @param _symbol symbol of inactive LP token
     */
    constructor(
        address _swapRouter,
        address _aaveLendingPool,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) Ownable() {
        swapRouter =  _swapRouter;
        aaveLendingPool = _aaveLendingPool;
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

        // minting corresponding amount of the inactive lp token to user
        _mint(msg.sender, tokenAmount);

        // transfer inputToken to the Cellar contract
        if (ERC20(inputToken).balanceOf(msg.sender) < tokenAmount)
            revert UserNotHaveEnoughBalance();
        TransferHelper.safeTransferFrom(
            inputToken,
            msg.sender,
            address(this),
            tokenAmount
        );

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
        TransferHelper.safeApprove(tokenIn, swapRouter, amountIn);

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
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        if (path.length < 2) revert PathIsTooShort();
        if (!inputTokens[tokenIn]) revert NonSupportedToken();
        if (!inputTokens[tokenOut]) revert NonSupportedToken();

        // Approve the router to spend first token in path
        TransferHelper.safeApprove(tokenIn, swapRouter, amountIn);

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
        _depositToAave(token, tokenAmount);

        // TODO: to change inactive_lp_shares into active_lp_shares
    }

    /**
     * @dev deposits cellar holdings into Aave lending pool
     * @param token the address of the token
     * @param tokenAmount the amount of token to be deposited
     **/
    function _depositToAave(address token, uint256 tokenAmount) internal {
        if (!inputTokens[token]) revert NonSupportedToken();
        if (tokenAmount == 0) revert ZeroAmount();

        ILendingPool lendingPool = ILendingPool(aaveLendingPool);

        // token verification in Aave protocol
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool
            .getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();

        // verification of liquidity
        if (tokenAmount > ERC20(token).balanceOf(address(this)))
            revert NotEnoughTokenLiquidity();

        TransferHelper.safeApprove(token, aaveLendingPool, tokenAmount);

        aaveDepositBalances[token] = aaveDepositBalances[token] + tokenAmount;

        // deposit token to Aave protocol
        lendingPool.deposit(token, tokenAmount, address(this), 0);

        emit DepositeToAave(token, tokenAmount, block.timestamp);
    }

    /**
     * @dev redeems an token from Aave protocol
     * @param token the address of the token
     * @param tokenAmount the token amount being redeemed
     **/
    function redeemFromAave(address token, uint256 tokenAmount)
        external
        onlyOwner
    {
        if (!inputTokens[token]) revert NonSupportedToken();
        if (tokenAmount == 0) revert ZeroAmount();

        ILendingPool lendingPool = ILendingPool(aaveLendingPool);

        // token verification in Aave protocol
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool
            .getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();

        // verification Aave deposit balance of token
        if (tokenAmount > aaveDepositBalances[token])
            revert InsufficientAaveDepositBalance();

        // withdraw token from Aave protocol
        lendingPool.withdraw(token, tokenAmount, address(this));

        aaveDepositBalances[token] = aaveDepositBalances[token] - tokenAmount;

        emit RedeemFromAave(token, tokenAmount, block.timestamp);
    }

    function initInputToken(address inputToken) public onlyOwner {
        if (inputTokens[inputToken]) revert TokenAlreadyInitialized();

        inputTokens[inputToken] = true;
        inputTokensList.push(inputToken);
    }
}
