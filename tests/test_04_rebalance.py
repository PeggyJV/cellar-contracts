#!/usr/bin/python3

import pytest

def test_empty(USDT, WETH, accounts, SwapRouter, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[0], 2 ** 256 - 1, 1000 * 10 ** 6, 1 * 10 ** 18, 0], {"from": accounts[0], "value": 1 * 10 ** 18})
    USDT.approve(CellarPoolShareContract, 1000 * 10 ** 6, {"from": accounts[0]})
    USDT_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    cellarRebalanceParams = [[0, 240000, 210000, 1], [0, 210000, 180000, 5], [0, 180000, 150000, 2]]
    cellarRebalanceParams = [[0, -150000, -180000, 1], [0, -180000, -210000, 5], [0,-210000, -240000, 2]]
    CellarPoolShareContract.rebalance(cellarRebalanceParams, {"from": accounts[1]})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == bal
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    cellarRemoveParams = [bal, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[0]})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == 0

def test_add_liquidity_ETH(USDT, WETH, accounts, SwapRouter, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[0], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[0], "value": 6 * 10 ** 18})
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[1], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[1], "value": 6 * 10 ** 18})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[0]})
    USDT.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[1]})
    USDT_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    cellarAddParams = [ETH_amount, USDT_amount, 0, 0, accounts[1], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == CellarPoolShareContract.balanceOf(accounts[1])

def test_rebalance(USDT, WETH, accounts, CellarPoolShareContract, Contract):
    cellarRebalanceParams = [[0, 240000, 210000, 1], [0, 210000, 180000, 5], [0, 180000, 150000, 2]]
    cellarRebalanceParams = [[0, -150000, -180000, 1], [0, -180000, -210000, 5], [0,-210000, -240000, 2]]
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    CellarPoolShareContract.rebalance(cellarRebalanceParams, {"from": accounts[1]})
    assert bal == CellarPoolShareContract.balanceOf(accounts[0])