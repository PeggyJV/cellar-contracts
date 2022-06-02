// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { MockAToken } from "./MockAToken.sol";

contract MockLendingPool {
    mapping(address => address) public aTokens;
    uint256 public index = 1000000000000000000000000000;

    constructor() {}

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
        ERC20(asset).transferFrom(onBehalfOf, aTokens[asset], amount);
        MockAToken(aTokens[asset]).mint(onBehalfOf, amount, index);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        if (amount == type(uint256).max) amount = MockAToken(aTokens[asset]).balanceOf(msg.sender);

        MockAToken(aTokens[asset]).burn(msg.sender, to, amount, index);

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
        aTokenAddress = aTokens[asset];
        stableDebtTokenAddress;
        variableDebtTokenAddress;
        interestRateStrategyAddress;
        id;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return index;
    }

    function initReserve(address asset, address aTokenAddress) external {
        aTokens[asset] = aTokenAddress;
    }
}
