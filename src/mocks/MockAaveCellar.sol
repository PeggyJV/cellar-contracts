// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IAaveIncentivesController } from "src/interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "src/interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "src/interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "src/interfaces/ISushiSwapRouter.sol";
import { IGravity } from "src/interfaces/IGravity.sol";
import { ILendingPool } from "src/interfaces/ILendingPool.sol";

import { AaveV2StablecoinCellar } from "src/AaveV2StablecoinCellar.sol";

contract MockAaveCellar is AaveV2StablecoinCellar {
    constructor(
        ERC20 _asset,
        address[] memory _approvedPositions,
        ICurveSwaps _curveRegistryExchange,
        ISushiSwapRouter _sushiswapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        IGravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        ERC20 _AAVE,
        ERC20 _WETH
    )
        AaveV2StablecoinCellar(
            _asset,
            _approvedPositions,
            _curveRegistryExchange,
            _sushiswapRouter,
            _lendingPool,
            _incentivesController,
            _gravityBridge,
            _stkAAVE,
            _AAVE,
            _WETH
        )
    {}

    function updatePosition(address newAsset) external {
        isTrusted[newAsset] = true;

        _updatePosition(newAsset);
    }
}
