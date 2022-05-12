// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { IAaveIncentivesController } from "../../interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "../../interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "../../interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "../../interfaces/ISushiSwapRouter.sol";
import { IGravity } from "../../interfaces/IGravity.sol";
import { ILendingPool } from "../../interfaces/ILendingPool.sol";

import { AaveV2StablecoinCellar } from "../../AaveV2StablecoinCellar.sol";

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
