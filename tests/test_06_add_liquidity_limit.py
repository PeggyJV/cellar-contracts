#!/usr/bin/python3

import pytest
import brownie

def test_add_liquidity_ETH(USDT, WETH, accounts, SwapRouter, CellarPoolShareLimitETHUSDTContract):
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[0], 2 ** 256 - 1, 30000 * 10 ** 6, 20 * 10 ** 18, 0], {"from": accounts[0], "value": 20 * 10 ** 18})
    USDT.approve(CellarPoolShareLimitETHUSDTContract, 2 ** 256 - 1, {"from": accounts[0]})
    USDT_amount = 5000 * 10 ** 6
    ETH_amount = 2 * 10 ** 18
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareLimitETHUSDTContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 2 * 10 ** 18})
    with brownie.reverts():
        CellarPoolShareLimitETHUSDTContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 2 * 10 ** 18})
