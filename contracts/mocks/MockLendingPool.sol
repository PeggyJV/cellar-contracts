// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./MockAToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLendingPool {
    address public aToken;
    uint256 public index = 1000000000000000000000000000;

    constructor(address _aToken) {
        aToken = address(_aToken);
    }

    // for testing purposes; not in actual contract
    function setLiquidityIndex(uint256 _index) external {
        index = _index;
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        IERC20(asset).transferFrom(onBehalfOf, aToken, amount);
        MockAToken(aToken).mint(onBehalfOf, amount, index);
    }

    function withdraw(
        address,
        uint256 amount,
        address to
    ) external returns (uint256) {
        MockAToken(aToken).burn(msg.sender, to, amount, index);
        return amount;
    }

    function getReserveData(address asset)
        external
        view
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
        liquidityIndex = uint128(index);
        variableBorrowIndex;
        currentLiquidityRate;
        currentVariableBorrowRate;
        currentStableBorrowRate;
        lastUpdateTimestamp;
        aTokenAddress = aToken;
        stableDebtTokenAddress;
        variableDebtTokenAddress;
        interestRateStrategyAddress;
        id;
    }
}
