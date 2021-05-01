//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    INonfungiblePositionManager
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

interface ICellarPoolShare is IERC20 {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct CellarParams {
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct CellarTickInfo {
        uint184 tokenId;
        int24 tickUpper;
        int24 tickLower;
        uint24 weight;
    }

    event AddedLiquidity(
        address indexed tokenId,
        address indexed token0,
        address indexed token1,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function addLiquidityForUniV3(CellarParams calldata cellarParams) external;
    function addLiquidityEthForUniV3(CellarParams calldata cellarParams)
        external
        payable;
    function reinvest() external;
    function setValidator(address _validator, bool value) external;
    function owner() external view override returns (address)
}

contract CellarPoolShare is ICellarPoolShare {
    using SafeERC20 for IERC20;

    address public constant NONFUNGIBLEPOSITIONMANAGER =
        0x048A595f1605BdC9732eBb967a1B9d9D9EE7E6Ff;

    address public constant UNISWAPV3FACTORY =
        0x048A595f1605BdC9732eBb967a1B9d9D9EE7E6Ff;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping (address => bool) public validator;
    uint256 private _totalSupply;
    address private _owner;
    string private _name;
    string private _symbol;

    address public token0;
    address public token1;

    uint256 public feeLevel;
    CellarTickInfo[] public cellarTickInfo;

    constructor(
        string memory name_,
        string memory symbol_,
        address _token0,
        address _token1,
        uint256 _feeLevel,
        CellarTickInfo[] calldata _cellarTickInfo
    ) {
        _name = name_;
        _symbol = symbol_;
        token0 = _token0;
        token1 = _token1;
        feeLevel = _feeLevel;
        for (uint256 i = 0; i < _cellarTickInfo.length; i++) {
            require(_cellarTickInfo[i].weight > 0, "Weight cannot be zero");
            require(_cellarTickInfo[i].tokenId == 0, "tokenId is not empty");
        }
        cellarTickInfo = _cellarTickInfo;
        _owner = msg.sender;
    }

    modifier onlyValidator() {
        require(validator[msg.sender], "Not validator");
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        public
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
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "transfer exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function addLiquidityForUniV3(CellarParams calldata cellarParams)
        external
        override
    {
        IERC20(token0).safeTransferFrom(
            msg.sender,
            address(this),
            uniV3Params.amount0Desired
        );
        IERC20(token1).safeTransferFrom(
            msg.sender,
            address(this),
            uniV3Params.amount1Desired
        );

        _addLiquidity(cellarParams);
    }

    function addLiquidityEthForUniV3(CellarParams cellarParams)
        external
        override
    {
        if (token0 == WETH) {
            if (msg.value > cellarParams.amount0Desired) {
                msg.sender.transfer(msg.value - cellarParams.amount0Desired);
            } else {
                require(
                    msg.value == cellarParams.amount0Desired,
                    "Eth not enough"
                );
            }
            IWETH(WETH).deposit{value: cellarParams.amount0Desired}();
            IERC20(token1).safeTransferFrom(
                msg.sender,
                address(this),
                cellarParams.amount1Desired
            );
        } else {
            require(token1 == WETH, "Not Eth Pair");
            if (msg.value > cellarParams.amount1Desired) {
                msg.sender.transfer(msg.value - cellarParams.amount1Desired);
            } else {
                require(
                    msg.value == cellarParams.amount1Desired,
                    "Eth not enough"
                );
            }
            IWETH(WETH).deposit{value: cellarParams.amount1Desired}();
            IERC20(cellarParams.token0).safeTransferFrom(
                msg.sender,
                address(this),
                uniV3Params.amount0Desired
            );
        }

        _addLiquidity(cellarParams);
    }

    function reinvest() external override onlyValidator {
        CellarTickInfo[] memory _cellarTickInfo = cellarTickInfo;
        uint256 weightSum;
        for (uint256 index = 0; index < _cellarTickInfo.length; index++) {
            require(_cellarTickInfo[index].tokenId != 0, "NFLP doesnot exist");
            weightSum += _cellarTickInfo[i].weight;
            INonfungiblePositionManager(NONFUNGIBLEPOSITIONMANAGER).collect(
                _cellarTickInfo[index].tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );
        }
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        if (balance0 > 0 && balance1 > 0) {
            for (uint256 index = 0; index < _cellarTickInfo.length; index++) {
                (uint128 liquidity, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(NONFUNGIBLEPOSITIONMANAGER).increaseLiquidity(
                    _cellarTickInfo[index].tokenId,
                    balance0 * _cellarTickInfo[index].weight / weightSum,
                    balance1 * _cellarTickInfo[index].weight / weightSum,
                    1,
                    1,
                    type(uint256).max
                );
            }
        }
    }

    function setValidator(address _validator, bool value) external override {
        require(msg.sender == _owner, "Not owner");
        validator[_validator] = value;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "transfer from zero address");
        require(recipient != address(0), "transfer to zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "transfer exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "mint to zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "burn from zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "burn exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "approve from zero address");
        require(spender != address(0), "approve to zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _addLiquidity(CellarParams memory cellarParams) internal {
        CellarTickInfo[] memory _cellarTickInfo = cellarTickInfo;
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).safeApprove(
            NONFUNGIBLEPOSITIONMANAGER,
            type(uint256).max
        );
        IERC20(_token1).safeApprove(
            NONFUNGIBLEPOSITIONMANAGER,
            type(uint256).max
        );
        uint24 weightSum;
        uint256 liquidityBefore;
        for (uint16 i = 0; i < _cellarTickInfo.length; i++) {
            weightSum += _cellarTickInfo[i].weight;
            if (_cellarTickInfo.tokenId > 0) {
                (, , , , , , , liquidity, , , , ) = INonfungiblePositionManager(
                    NONFUNGIBLEPOSITIONMANAGER
                )
                    .positions(_cellarTickInfo[i].tokenId);
                liquidityBefore += liquidity;
            }
        }
        uint256 retAmount0;
        uint256 retAmount1;
        uint256 liquiditySum;
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        for (uint16 i = 0; i < _cellarTickInfo.length; i++) {
            uint256 amount0Desired =
                (cellarParams.amount0Desired * _cellarTickInfo[i].weight) /
                    weightSum;
            uint256 amount1Desired =
                (cellarParams.amount1Desired * _cellarTickInfo[i].weight) /
                    weightSum;
            uint256 amount0Min =
                (cellarParams.amount0Min * _cellarTickInfo[i].weight) /
                    weightSum;
            uint256 amount1Min =
                (cellarParams.amount1Min * _cellarTickInfo[i].weight) /
                    weightSum;
            if (_cellarTickInfo[i].tokenId == 0) {
                MintParams memory mintParams =
                    MintParams({
                        token0: _token0,
                        token1: _token1,
                        fee: feeLevel,
                        tickLower: _cellarTickInfo[i].tickLower,
                        tickUpper: _cellarTickInfo[i].tickUpper,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: amount0Min,
                        amount1Min: amount1Min,
                        recipient: address(this),
                        deadline: cellarParams.deadline
                    });
                (
                    tokenId,
                    liquidity,
                    amount0,
                    amount1
                ) = INonfungiblePositionManager(NONFUNGIBLEPOSITIONMANAGER)
                    .mint(mintParams);
                cellarTickInfo[i].tokenId = tokenId;
                if (amount0 < amount0Desired) {
                    retAmount0 += amount0Desired - amount0;
                }
                if (amount1 < amount1Desired) {
                    retAmount1 += amount1Desired - amount1;
                }
            } else {
                (liquidity, amount0, amount1) = INonfungiblePositionManager(
                    NONFUNGIBLEPOSITIONMANAGER
                )
                    .increaseLiquidity(
                    _cellarTickInfo[i].tokenId,
                    amount0Desired,
                    amount1Desired,
                    amount0Min,
                    amount1Min,
                    cellarParams.deadline
                );
                if (amount0 < amount0Desired) {
                    retAmount0 += amount0Desired - amount0;
                }
                if (amount1 < amount1Desired) {
                    retAmount1 += amount1Desired - amount1;
                }
            }
            liquiditySum += liquidity;
        }

        uint256 inAmount0 = cellarParams.amount0Desired - retAmount0;
        uint256 inAmount1 = cellarParams.amount1Desired - retAmount1;
        require(inAmount0 >= cellarParams.amount0Min, "Less than Amount0Min");
        require(inAmount1 >= cellarParams.amount1Min, "Less than Amount1Min");
        _mint(msg.sender, (liquiditySum * _totalSupply) / liquidityBefore);
        IERC20(_token0).safeTransfer(msg.sender, retAmount0);
        IERC20(_token0).safeApprove(NONFUNGIBLEPOSITIONMANAGER, 0);
        IERC20(_token1).safeTransfer(msg.sender, retAmount1);
        IERC20(_token1).safeApprove(NONFUNGIBLEPOSITIONMANAGER, 0);
        emit AddedLiquidity(
            tokenId_,
            _token0,
            _token1,
            liquidity,
            cellarParams.amount0Desired - retAmount0,
            cellarParams.amount1Desired - retAmount1
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
