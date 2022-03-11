// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./MockToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLendingPool {
    address public aToken;

    constructor(string memory _symbol) {
        MockToken token = new MockToken(string(abi.encodePacked("a", _symbol)));
        aToken = address(token);
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        IERC20(asset).transferFrom(onBehalfOf, address(this), amount);
        MockToken(aToken).mint(onBehalfOf, amount);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        if (amount == type(uint256).max)
            amount = MockToken(aToken).balanceOf(msg.sender);
        MockToken(aToken).burn(to, amount);
        IERC20(asset).transfer(to, amount);
        return amount;
    }

    function getReserveData(address asset)
    external
    pure
    returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 variableBorrowIndex,
        uint128 currentLiquidityRate,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint8 id
    )
    {
        asset;
        configuration;
        liquidityIndex;
        variableBorrowIndex;
        currentLiquidityRate;
        currentVariableBorrowRate;
        currentStableBorrowRate;
        lastUpdateTimestamp;
        aTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // We only care about this for now
        stableDebtTokenAddress;
        variableDebtTokenAddress;
        interestRateStrategyAddress;
        id;
    }
}
