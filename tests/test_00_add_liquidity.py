#!/usr/bin/python3

import pytest

def test_add_liquidity_ETH(USDT, WETH, accounts, SwapRouter, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[0], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[0], "value": 6 * 10 ** 18})
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[1], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[1], "value": 6 * 10 ** 18})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[0]})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[1]})
    USDT_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == CellarPoolShareContract.balanceOf(accounts[1])

def test_add_liquidity(USDT, WETH, accounts, CellarPoolShareContract):
    WETH.deposit({"from": accounts[0], "value": 3 * 10 ** 18})
    WETH.deposit({"from": accounts[1], "value": 3 * 10 ** 18})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[0]})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[1]})
    WETH.approve(CellarPoolShareContract, 3 * 10 ** 18, {"from": accounts[0]})
    WETH.approve(CellarPoolShareContract, 3 * 10 ** 18, {"from": accounts[1]})
    USDT_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0]})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0]})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[0]})
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1]})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1]})
    CellarPoolShareContract.addLiquidityForUniV3(cellarAddParams, {"from": accounts[1]})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == CellarPoolShareContract.balanceOf(accounts[1])
