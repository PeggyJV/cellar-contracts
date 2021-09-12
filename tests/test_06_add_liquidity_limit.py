#!/usr/bin/python3

import pytest
import brownie

def test_add_liquidity_ETH(USDC, WETH, accounts, SwapRouter, CellarPoolShareLimitUSDCETHContract):
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[0], 2 ** 256 - 1, 30000 * 10 ** 6, 20 * 10 ** 18, 0], {"from": accounts[0], "value": 20 * 10 ** 18})
    USDC.approve(CellarPoolShareLimitUSDCETHContract, 2 ** 256 - 1, {"from": accounts[0]})
    USDC_amount = 5000 * 10 ** 6
    ETH_amount = 2 * 10 ** 18
    cellarAddParams = [USDC_amount, ETH_amount, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareLimitUSDCETHContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0], "value": 2 * 10 ** 18})
    with brownie.reverts():
        CellarPoolShareLimitUSDCETHContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0], "value": 2 * 10 ** 18})
