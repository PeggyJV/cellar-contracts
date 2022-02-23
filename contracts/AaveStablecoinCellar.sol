// SPDX-License-Identifier: Apache-2.0
// VolumeFi Software, Inc.

pragma solidity 0.8.11;

import './interfaces/IAaveStablecoinCellar.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import './interfaces/ILendingPool.sol';

/**
 * @title Sommelier AaveStablecoinCellar contract
 * @notice AaveStablecoinCellar contract for Sommelier Network
 * @author VolumeFi Software
 */
contract AaveStablecoinCellar is IAaveStablecoinCellar {
    using SafeERC20 for IERC20;

    // Uniswap Router V3 contract address
    address private constant _SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    
    // Aave Lending Pool V2 contract address
    address private constant _AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    
    address private constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // Declare the variables and mappings
    mapping(address => uint256) private _balances;
    
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    address private _owner;
    bool private _isEntered;
    string private _name;
    string private _symbol;
    
    address[] public input_tokens_list;
    mapping(address => bool) internal input_tokens;
    
    uint24 public constant poolFee = 3000;
    
    // Aave deposit balances by tokens
    mapping(address => uint256) public aaveDepositBalances;
    
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NonPermission();
        _;
    }
    
    modifier nonReentrant() {
        if (_isEntered) revert Reentrance();
        _isEntered = true;
        _;
        _isEntered = false;
    }
    
    /**
     * @notice Constructor identifies the name and symbol of the inactive lp token
     */
    constructor(
        string memory name_,
        string memory symbol_
    ) {
        _name = name_;
        _symbol = symbol_;

        _owner = msg.sender;
    }
    
    /**
     * @dev adds liquidity (the supported token) into the cellar. 
     * A corresponding amount of the inactive lp token is minted.
     * @param input_token the address of the token
     * @param token_amount the amount to be added
     **/
    function addLiquidity(address input_token, uint256 token_amount) external {
        if (!input_tokens[input_token]) revert NonSupportedToken();
        
        if (token_amount == 0) revert ZeroAmount();
        
        // minting corresponding amount of the inactive lp token to user
        _mint(msg.sender, token_amount);
        
        // transfer input_token to the Cellar contract
        if (IERC20(input_token).balanceOf(msg.sender) < token_amount) revert UserNotHaveEnoughBalance();
        TransferHelper.safeTransferFrom(input_token, msg.sender, address(this), token_amount);
        
        emit AddedLiquidity(input_token, msg.sender, token_amount, block.timestamp);
    }
    
    /**
     * @dev swaps input token by Uniswap V3
     * @param tokenIn the address of the incoming token
     * @param tokenOut the address of the outgoing token
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     **/
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMinimum) external onlyOwner returns (uint256 amountOut) {
        if (!input_tokens[tokenIn]) revert NonSupportedToken();
        if (!input_tokens[tokenOut]) revert NonSupportedToken();
        
        // Approve the router to spend tokenIn
        TransferHelper.safeApprove(tokenIn, _SWAP_ROUTER, amountIn);
        
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        
        // Executes the swap.
        amountOut = ISwapRouter(_SWAP_ROUTER).exactInputSingle(params);
        
        emit Swapped(tokenIn, amountIn, tokenOut, amountOut, block.timestamp);
    }
    
    /**
     * @dev swaps tokens by multihop swap in Uniswap V3
     * @param path the token swap path (token addresses)
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     **/
    function multihopSwap(address[] memory path, uint256 amountIn, uint256 amountOutMinimum) external onlyOwner returns (uint256 amountOut) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        
        if (path.length < 2) revert PathIsTooShort();
        if (!input_tokens[tokenIn]) revert NonSupportedToken();
        if (!input_tokens[tokenOut]) revert NonSupportedToken();
        
        // Approve the router to spend first token in path
        TransferHelper.safeApprove(tokenIn, _SWAP_ROUTER, amountIn);

        bytes memory encodePackedPath = abi.encodePacked(tokenIn);
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(encodePackedPath, poolFee, path[i]);
        }
        
        // Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
        // The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: encodePackedPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

        // Executes the swap.
        amountOut = ISwapRouter(_SWAP_ROUTER).exactInput(params);
        
        emit Swapped(tokenIn, amountIn, tokenOut, amountOut, block.timestamp);
    }
    
    /**
     * @dev enters Aave Stablecoin Strategy
     * @param token the address of the token
     * @param token_amount the amount of token to be deposited
     **/
    function enterStrategy(address token, uint256 token_amount) external onlyOwner {
        // deposits to Aave
        _depositeToAave(token, token_amount);
        
        // TODO: to change inactive_lp_shares into active_lp_shares
    }
    
    /**
     * @dev deposits cellar holdings into Aave lending pool
     * @param token the address of the token
     * @param token_amount the amount of token to be deposited
     **/
    function _depositeToAave(address token, uint256 token_amount) internal {
        if (!input_tokens[token]) revert NonSupportedToken();
        if (token_amount == 0) revert ZeroAmount();
        
        ILendingPool aaveLendingPool = ILendingPool(_AAVE_LENDING_POOL);
        
        // token verification in Aave protocol
        ( , , , , , , , address aTokenAddress, , , , ) = aaveLendingPool.getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();
                
        // verification of liquidity
        if (token_amount > IERC20(token).balanceOf(address(this))) revert NotEnoughTokenLiquidity();
       
        TransferHelper.safeApprove(token, _AAVE_LENDING_POOL, token_amount);
            
        aaveDepositBalances[token] = aaveDepositBalances[token] + token_amount;
        
        // deposit token to Aave protocol
        aaveLendingPool.deposit(
            token,
            token_amount,
            address(this),
            0
        );
        
        emit DepositeToAave(token, token_amount, block.timestamp);
    }
    
    /**
    * @dev redeems an token from Aave protocol
    * @param token the address of the token
    * @param token_amount the token amount being redeemed
    **/
    function redeemFromAave(address token, uint256 token_amount)
        external
        onlyOwner
    {
        if (!input_tokens[token]) revert NonSupportedToken();
        if (token_amount == 0) revert ZeroAmount();
        
        ILendingPool aaveLendingPool = ILendingPool(_AAVE_LENDING_POOL);
        
        // token verification in Aave protocol
        ( , , , , , , , address aTokenAddress, , , , ) = aaveLendingPool.getReserveData(token);
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave();
        
        // verification Aave deposit balance of token
        if (token_amount > aaveDepositBalances[token]) revert InsufficientAaveDepositBalance();
        
        // withdraw token from Aave protocol
        aaveLendingPool.withdraw(
            token,
            token_amount,
            address(this)
        );
        
        aaveDepositBalances[token] = aaveDepositBalances[token] - token_amount;
        
        emit RedeemFromAave(token, token_amount, block.timestamp);
    }
    
    function initInputToken(
        address input_token
    ) public onlyOwner {
        if (input_tokens[input_token]) revert TokenAlreadyInitialized();
        
        input_tokens[input_token] = true;
        input_tokens_list.push(input_token);
    }
    
//////////////////////////////////////////////////////////////////////////////////////////////////////////
    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function transferOwnership(address newOwner) external override onlyOwner {
        if (newOwner == address(0)) revert InvalidInput();
        _owner = newOwner;
        emit TransferOwnership(newOwner);
    }


    function owner() external view override returns (address) {
        return _owner;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function allowance(address owner_, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner_][spender];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (sender == address(0)) revert TransferFromZeroAddress();
        if (recipient == address(0)) revert TransferToZeroAddress();

        _balances[sender] -= amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert MintToZeroAddress();

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert BurnFromZeroAddress();

        _balances[account] -= amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner_,
        address spender,
        uint256 amount
    ) internal {
        if (owner_ == address(0)) revert ApproveFromZeroAddress();
        if (spender == address(0)) revert ApproveToZeroAddress();

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    receive() external payable {
        require(msg.sender == _WETH);
    }
}
