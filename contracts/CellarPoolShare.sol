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

import {
    FixedPoint96
} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";

import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

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
        uint256 indexed tokenId,
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

    function owner() external view returns (address);
}

interface IWETH {
    function deposit() external payable;
}

contract CellarPoolShare is ICellarPoolShare {
    using SafeERC20 for IERC20;

    address public constant NONFUNGIBLEPOSITIONMANAGER =
        0x048A595f1605BdC9732eBb967a1B9d9D9EE7E6Ff;

    address public constant UNISWAPV3FACTORY =
        0x048A595f1605BdC9732eBb967a1B9d9D9EE7E6Ff;

    address public constant WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public validator;
    uint256 private _totalSupply;
    address private _owner;
    string private _name;
    string private _symbol;

    address public token0;
    address public token1;

    uint24 public feeLevel;
    CellarTickInfo[] public cellarTickInfo;

    constructor(
        string memory name_,
        string memory symbol_,
        address _token0,
        address _token1,
        uint24 _feeLevel,
        CellarTickInfo[] memory _cellarTickInfo
    ) {
        _name = name_;
        _symbol = symbol_;
        require(_token0 < _token1, "Tokens are not sorted");
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
        _;
    }

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
            cellarParams.amount0Desired
        );
        IERC20(token1).safeTransferFrom(
            msg.sender,
            address(this),
            cellarParams.amount1Desired
        );

        _addLiquidity(cellarParams);
    }

    function addLiquidityEthForUniV3(CellarParams calldata cellarParams)
        external
        payable
        override
    {
        address _token0 = token0;
        if (_token0 == WETH) {
            if (msg.value > cellarParams.amount0Desired) {
                payable(msg.sender).transfer(
                    msg.value - cellarParams.amount0Desired
                );
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
                payable(msg.sender).transfer(
                    msg.value - cellarParams.amount1Desired
                );
            } else {
                require(
                    msg.value == cellarParams.amount1Desired,
                    "Eth not enough"
                );
            }
            IWETH(WETH).deposit{value: cellarParams.amount1Desired}();
            IERC20(_token0).safeTransferFrom(
                msg.sender,
                address(this),
                cellarParams.amount0Desired
            );
        }

        _addLiquidity(cellarParams);
    }

    function reinvest() external override onlyValidator {
        CellarTickInfo[] memory _cellarTickInfo = cellarTickInfo;
        uint256 weightSum;
        for (uint256 index = 0; index < _cellarTickInfo.length; index++) {
            require(_cellarTickInfo[index].tokenId != 0, "NFLP doesnot exist");
            weightSum += _cellarTickInfo[index].weight;
            INonfungiblePositionManager(NONFUNGIBLEPOSITIONMANAGER).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: _cellarTickInfo[index].tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        if (balance0 > 0 && balance1 > 0) {
            _addLiquidity(
                CellarParams({
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );
        }
    }

    function setValidator(address _validator, bool value) external override {
        require(msg.sender == _owner, "Not owner");
        validator[_validator] = value;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender)
        public
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
        address owner_,
        address spender,
        uint256 amount
    ) internal {
        require(owner_ != address(0), "approve from zero address");
        require(spender != address(0), "approve to zero address");

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _addLiquidity(CellarParams memory cellarParams) internal {
        CellarTickInfo[] memory _cellarTickInfo = cellarTickInfo;
        address _token0 = token0;
        address _token1 = token1;
        uint24 _feeLevel = feeLevel;
        IERC20(_token0).safeApprove(
            NONFUNGIBLEPOSITIONMANAGER,
            type(uint256).max
        );
        IERC20(_token1).safeApprove(
            NONFUNGIBLEPOSITIONMANAGER,
            type(uint256).max
        );
        uint256 weightSum0;
        uint256 weightSum1;
        uint256[] memory weight0 = new uint256[](_cellarTickInfo.length);
        uint256[] memory weight1 = new uint256[](_cellarTickInfo.length);
        uint160 sqrtPriceX96;
        uint256 liquidityBefore;
        address pool =
            IUniswapV3Factory(UNISWAPV3FACTORY).getPool(
                _token0,
                _token1,
                _feeLevel
            );
        int24 currentTick;
        uint128 liquidity;
        (sqrtPriceX96, currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        for (uint16 i = 0; i < _cellarTickInfo.length; i++) {
            if (_cellarTickInfo[i].tokenId > 0) {
                (, , , , , , , liquidity, , , , ) = INonfungiblePositionManager(
                    NONFUNGIBLEPOSITIONMANAGER
                )
                    .positions(_cellarTickInfo[i].tokenId);
                liquidityBefore += liquidity;
            }
            if (currentTick <= _cellarTickInfo[i].tickLower) {
                weight0[i] = _cellarTickInfo[i].weight * FixedPoint96.Q96;
                weightSum0 += weight0[i];
            } else if (currentTick >= _cellarTickInfo[i].tickUpper) {
                weight1[i] += _cellarTickInfo[i].weight * FixedPoint96.Q96;
                weightSum1 += weight1[i];
            } else {
                uint160 sqrtPriceAX96 =
                    TickMath.getSqrtRatioAtTick(_cellarTickInfo[i].tickLower);
                uint160 sqrtPriceBX96 =
                    TickMath.getSqrtRatioAtTick(_cellarTickInfo[i].tickUpper);
                (weight0[i], weight1[i]) = _getWeights(
                    sqrtPriceAX96,
                    sqrtPriceBX96,
                    sqrtPriceX96,
                    _cellarTickInfo[i].weight
                );
                weightSum0 += weight0[i];
                weightSum1 += weight1[i];
            }
        }
        uint256 inAmount0;
        uint256 inAmount1;
        uint128 liquiditySum;
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
        for (uint16 i = 0; i < _cellarTickInfo.length; i++) {
            uint256 amount0Desired;
            uint256 amount0Min;
            uint256 amount1Desired;
            uint256 amount1Min;
            if (weightSum0 > 0) {
                amount0Desired = FullMath.mulDiv(
                    cellarParams.amount0Desired,
                    weight0[i],
                    weightSum0
                );
                amount0Min = FullMath.mulDiv(
                    cellarParams.amount0Min,
                    weight0[i],
                    weightSum0
                );
            }
            if (weightSum1 > 0) {
                amount1Desired = FullMath.mulDiv(
                    cellarParams.amount1Desired,
                    weight1[i],
                    weightSum1
                );
                amount1Min = FullMath.mulDiv(
                    cellarParams.amount1Min,
                    weight1[i],
                    weightSum1
                );
            }
            if (_cellarTickInfo[i].tokenId == 0) {
                (
                    tokenId,
                    liquidity,
                    amount0,
                    amount1
                ) = INonfungiblePositionManager(NONFUNGIBLEPOSITIONMANAGER)
                    .mint(
                    INonfungiblePositionManager.MintParams({
                        token0: _token0,
                        token1: _token1,
                        fee: _feeLevel,
                        tickLower: _cellarTickInfo[i].tickLower,
                        tickUpper: _cellarTickInfo[i].tickUpper,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: amount0Min,
                        amount1Min: amount1Min,
                        recipient: address(this),
                        deadline: cellarParams.deadline
                    })
                );
                cellarTickInfo[i].tokenId = uint184(tokenId);
                inAmount0 += amount0;
                inAmount1 += amount1;
            } else {
                tokenId = _cellarTickInfo[i].tokenId;
                (liquidity, amount0, amount1) = INonfungiblePositionManager(
                    NONFUNGIBLEPOSITIONMANAGER
                )
                    .increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams({
                        tokenId: _cellarTickInfo[i].tokenId,
                        amount0Desired: amount0Desired,
                        amount1Desired: amount1Desired,
                        amount0Min: amount0Min,
                        amount1Min: amount1Min,
                        deadline: cellarParams.deadline
                    })
                );
                inAmount0 += amount0;
                inAmount1 += amount1;
            }
            liquiditySum += liquidity;
        }

        require(inAmount0 >= cellarParams.amount0Min, "Less than Amount0Min");
        require(inAmount1 >= cellarParams.amount1Min, "Less than Amount1Min");

        uint256 retAmount0 = cellarParams.amount0Desired - inAmount0;
        uint256 retAmount1 = cellarParams.amount1Desired - inAmount1;
        _mint(msg.sender, (liquiditySum * _totalSupply) / liquidityBefore);
        IERC20(_token0).safeTransfer(msg.sender, retAmount0);
        IERC20(_token0).safeApprove(NONFUNGIBLEPOSITIONMANAGER, 0);
        IERC20(_token1).safeTransfer(msg.sender, retAmount1);
        IERC20(_token1).safeApprove(NONFUNGIBLEPOSITIONMANAGER, 0);
        emit AddedLiquidity(
            tokenId,
            _token0,
            _token1,
            liquiditySum,
            inAmount0,
            inAmount1
        );
    }

    function _getWeights(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint160 sqrtPriceX96,
        uint24 weight
    ) internal returns (uint256 weight0, uint256 weight1) {
        weight0 =
            FullMath.mulDiv(
                FullMath.mulDiv(
                    FullMath.mulDiv(
                        sqrtPriceAX96,
                        (sqrtPriceBX96 - sqrtPriceX96),
                        FixedPoint96.Q96
                    ),
                    FixedPoint96.Q96,
                    sqrtPriceX96
                ),
                FixedPoint96.Q96,
                (sqrtPriceBX96 - sqrtPriceAX96)
            ) *
            weight;
        weight1 =
            FullMath.mulDiv(
                (sqrtPriceX96 - sqrtPriceAX96),
                FixedPoint96.Q96,
                (sqrtPriceBX96 - sqrtPriceAX96)
            ) *
            weight;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
