// SPDX-License-Identifier: Apache-2.0
// VolumeFi Software, Inc.

pragma solidity 0.8.11;

import './interfaces/ICellar.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

/**
 * @title Sommelier Cellar contract
 * @notice Cellar contract for Sommelier Network
 * @author VolumeFi Software
 */

contract Cellar is ICellar {
    using SafeERC20 for IERC20;

    // Set the Uniswap V3 contract Addresses.
    address private constant _SWAPROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

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
    
    uint24 public constant poolFee = 0;
    
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NonPermission();
        _;
    }

    modifier onlyValidator() {
        if (!validator[msg.sender]) revert NonPermission();
        _;
    }

    modifier nonReentrant() {
        if (_isEntered) revert Reentrance();
        _isEntered = true;
        _;
        _isEntered = false;
    }

    /**
    * @dev only supported input tokens can use functions affected by this modifier
    **/
    modifier onlySupportedTokens {
        if (!input_tokens[input_token]) revert NonSupportedToken();
        _;
    }
    
    /**
     * @notice Constructor identifies the name and symbol of the inactive lp token
     */
    constructor(
        string memory name_,
        string memory symbol_,
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
    function addLiquidity(address input_token, uint256 token_amount) external onlySupportedTokens {
        require(token_amount > 0, "Amount must be greater than 0");
        
        // minting corresponding amount of the inactive lp token to user
        mint(msg.sender, token_amount);
        
        // transfer input_token to the Cellar contract
        if (IERC20(input_token).balanceOf(msg.sender) < token_amount) revert userNotHaveEnoughBalance();
        TransferHelper.safeTransferFrom(input_token, msg.sender, address(this), token_amount);
        
        emit AddedLiquidity(input_token, msg.sender, token_amount, block.timestamp);
    }
    
    /**
     * @dev swaps input token by Uniswap V3
     * @param _token0 the address of the incoming token
     * @param _token1 the address of the outgoing token
     * @param amountIn the amount of tokens to be swapped
     * @return amountOut
     **/
    function swap(address _token0, address _token1, uint256 amountIn) external onlyOwner onlySupportedTokens returns (uint256 amountOut) {
        // Approve the router to spend _token0
        TransferHelper.safeApprove(IERC20(_token0), _SWAPROUTER, amountIn);

        // Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
        // The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(IERC20(_token0), poolFee, IERC20(_token1)),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        // Executes the swap.
        amountOut = ISwapRouter(_SWAPROUTER).exactInput(params);
        
        emit Swapped(_token0, amountIn, _token1, amountOut, block.timestamp);
    }
    
    function initInputToken(
        address input_token
    ) public onlyOwner {
        require(!input_tokens[input_token], "Asset has already been initialized");

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
