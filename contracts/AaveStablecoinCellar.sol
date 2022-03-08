// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import "./interfaces/IAaveStablecoinCellar.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ILendingPool.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAToken.sol";
import "./utils/MathUtils.sol";

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

    struct Deposit {
        uint256 amount;
        uint256 shares;
        uint256 timeDeposited;
    }

    // Uniswap Router V3 contract address
    address private immutable swapRouter; // 0xE592427A0AEce92De3Edee1F18E0157C05861564

    // Aave Lending Pool V2 contract address
    address private immutable aaveLendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9

    // Declare the variables and mappings
    address[] public inputTokensList;
    mapping(address => bool) internal inputTokens;
    address private immutable currentLendingToken;
    address private immutable currentAToken;
    // Track user user deposits to determine active/inactive shares
    mapping(address => Deposit[]) public userDeposits;
    // Store the index of the user's last non-zero deposit to save gas on looping
    mapping(address => uint256) public currentDepositIndex;
    // Last time inactive funds were entered into a strategy and made active
    uint256 public lastTimeEnteredStrategy;
    uint256 public totalActiveShares;

    uint24 public constant POOL_FEE = 3000;

    // Aave deposit balances by tokens
    mapping(address => uint256) public aaveDepositBalances;

    /**
     * @notice Constructor identifies the name and symbol of the inactive lp token
     * @param _swapRouter Uniswap V3 swap router address
     * @param _aaveLendingPool Aave V2 lending pool address
     * @param _currentLendingToken token of lending pool where the cellar has its liquidity deposited
     * @param _name name of inactive LP token
     * @param _symbol symbol of inactive LP token
     */
    constructor(
        address _swapRouter,
        address _aaveLendingPool,
        address _currentLendingToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) Ownable() {
        swapRouter =  _swapRouter;
        aaveLendingPool = _aaveLendingPool;
        currentLendingToken = _currentLendingToken;

        (, , , , , , , address aTokenAddress, , , , ) = ILendingPool(aaveLendingPool)
            .getReserveData(currentLendingToken);
        currentAToken = aTokenAddress;
    }

    /**
     * @dev adds liquidity (the supported token) into the cellar.
     * A corresponding amount of the shares is minted.
     * @param inputToken the address of the token
     * @param amount the amount to be added
     **/
    function addLiquidity(address inputToken, uint256 amount) external {
        if (!inputTokens[inputToken]) revert NonSupportedToken();

        if (amount == 0) revert ZeroAmount();

        if (ERC20(inputToken).balanceOf(msg.sender) < amount)
            revert UserNotHaveEnoughBalance();

        ERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = convertToShares(amount);
        _mint(msg.sender, shares);

        Deposit[] storage deposits = userDeposits[msg.sender];
        deposits.push(Deposit({
            amount: amount,
            shares: shares,
            timeDeposited: block.timestamp
        }));

        emit AddedLiquidity(
            inputToken,
            msg.sender,
            amount,
            block.timestamp
        );
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // burn proportional amount of user shares
        uint256 shares = convertToShares(amount);
        _burn(msg.sender, shares);

        uint256 inactiveAmount;
        uint256 activeShares;

        Deposit[] storage deposits = userDeposits[msg.sender];
        uint256 currentIdx = currentDepositIndex[msg.sender];

        for (uint256 i = currentIdx; i < deposits.length; i++) {
            Deposit storage deposit = deposits[i];

            uint256 withdrawnAmount;
            uint256 withdrawnShares;

            if (deposit.amount <= amount) {
                withdrawnAmount = deposit.amount;
                withdrawnShares = deposit.shares;
            } else {
                withdrawnAmount = amount;
                withdrawnShares = deposit.shares * (amount / deposit.amount);
            }

            if (deposit.timeDeposited < lastTimeEnteredStrategy) {
                activeShares += withdrawnShares;
            } else {
                inactiveAmount += withdrawnAmount;
            }

            deposit.amount -= withdrawnAmount;
            deposit.shares -= withdrawnShares;

            amount -= withdrawnAmount;

            if (amount == 0) {
                if (deposit.amount != 0) {
                    currentDepositIndex[msg.sender] = i;
                } else {
                    currentDepositIndex[msg.sender] = i + 1;
                }

                break;
            }
        }

        (, uint256 liquidityIndex, , , , , , , , , , ) = ILendingPool(aaveLendingPool)
            .getReserveData(currentLendingToken);

        // convert from shares -> aTokens -> amount of tokens Aave with exchange for amount of aTokens.
        // necessary to do because with Aave `withdraw` function you must specify the amount of tokens
        // you want to receive, not the amount of aTokens you want to redeem
        uint256 aTokenAmount = convertToAssets(activeShares);
        // refer to the `burn` function in Aave's AToken.sol to understand why this is necessary
        uint256 activeAmount = MathUtils.rayMulDown(aTokenAmount, liquidityIndex);

        uint256 totalWithdrawAmount = activeAmount + inactiveAmount;

        // withdraw user tokens from Aave to user
        ILendingPool(aaveLendingPool).withdraw(currentLendingToken, totalWithdrawAmount, msg.sender);

        totalActiveShares -= activeShares;
    }

    function totalAssets() public view returns (uint256) {
        return IAToken(currentAToken).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return totalActiveShares == 0 ? assets : MathUtils.mulDivDown(assets, totalActiveShares, totalAssets());
    }

    function convertToAssets(uint256 activeShares) public view returns (uint256) {
        return totalActiveShares == 0 ?
            activeShares :
            MathUtils.mulDivDown(activeShares, totalAssets(), totalActiveShares);
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
     * @param amount the amount of token to be deposited
     **/
    function enterStrategy(address token, uint256 amount)
        external
        onlyOwner
    {
        // deposits to Aave
        _depositToAave(token, amount);

        uint256 shares = convertToShares(amount);
        totalActiveShares += shares;

        // TODO: to change inactive_lp_shares into active_lp_shares
    }

    /**
     * @dev deposits cellar holdings into Aave lending pool
     * @param token the address of the token
     * @param amount the amount of token to be deposited
     **/
    function _depositToAave(address token, uint256 amount) internal {
        if (!inputTokens[token]) revert NonSupportedToken();
        if (amount == 0) revert ZeroAmount();

        ILendingPool lendingPool = ILendingPool(aaveLendingPool);

        // token verification in Aave protocol
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool
            .getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();

        // verification of liquidity
        if (amount > ERC20(token).balanceOf(address(this)))
            revert NotEnoughTokenLiquidity();

        ERC20(token).safeApprove(aaveLendingPool, amount);

        aaveDepositBalances[token] += amount;

        // deposit token to Aave protocol
        lendingPool.deposit(token, amount, address(this), 0);

        emit DepositeToAave(token, amount, block.timestamp);
    }

    /**
     * @dev redeems an token from Aave protocol
     * @param token the address of the token
     * @param amount the token amount being redeemed
     **/
    function redeemFromAave(address token, uint256 amount)
        external
        onlyOwner
    {
        if (!inputTokens[token]) revert NonSupportedToken();
        if (amount == 0) revert ZeroAmount();

        ILendingPool lendingPool = ILendingPool(aaveLendingPool);

        // token verification in Aave protocol
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool
            .getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();

        // verification Aave deposit balance of token
        if (amount > aaveDepositBalances[token])
            revert InsufficientAaveDepositBalance();

        // withdraw token from Aave protocol
        lendingPool.withdraw(token, amount, address(this));

        aaveDepositBalances[token] -= amount;

        emit RedeemFromAave(token, amount, block.timestamp);
    }

    function initInputToken(address inputToken) public onlyOwner {
        if (inputTokens[inputToken]) revert TokenAlreadyInitialized();

        inputTokens[inputToken] = true;
        inputTokensList.push(inputToken);
    }
}
