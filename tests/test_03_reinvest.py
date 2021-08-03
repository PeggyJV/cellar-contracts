#!/usr/bin/python3

import pytest

def test_empty(USDC, WETH, accounts, SwapRouter, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[2], 2 ** 256 - 1, 10000 * 10 ** 6, 5 * 10 ** 18, 0], {"from": accounts[2], "value": 5 * 10 ** 18})
    USDC.approve(CellarPoolShareContract, 10000 * 10 ** 6, {"from": accounts[2]})
    USDC_amount = 10000 * 10 ** 6
    ETH_amount = 5 * 10 ** 18
    cellarAddParams = [USDC_amount, ETH_amount, 0, 0, accounts[2], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[2], "value": 5 * 10 ** 18})
    CellarPoolShareContract.setValidator(accounts[2], True, {"from": accounts[0]})
    for i in range(3):
        SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[3], 2 ** 256 - 1, 10000 * 10 ** 6, 5 * 10 ** 18, 0], {"from": accounts[3], "value": 5 * 10 ** 18})
        USDC.approve(SwapRouter, 100000 * 10 ** 6, {"from": accounts[3]})
        SwapRouter.exactInputSingle([USDC, WETH, 3000, accounts[3], 2 ** 256 - 1, 10000 * 10 ** 6, 5 * 10 ** 17, 0], {"from": accounts[3]})
        WETH.withdraw(WETH.balanceOf(accounts[3]), {"from": accounts[3]})
    tx = CellarPoolShareContract.reinvest({"from": accounts[2]})
    bal = CellarPoolShareContract.balanceOf(accounts[2])
    cellarRemoveParams = [bal, 0, 0, accounts[2], 2 ** 256 - 1]
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[2]})
    assert CellarPoolShareContract.balanceOf(accounts[2]) == 0

def test_add_liquidity_ETH(USDC, WETH, accounts, SwapRouter, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[0], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[0], "value": 6 * 10 ** 18})
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[1], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[1], "value": 6 * 10 ** 18})
    USDC.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[0]})
    USDC.approve(CellarPoolShareContract, 3000 * 10 ** 6, {"from": accounts[1]})
    USDC_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [USDC_amount, ETH_amount, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    cellarAddParams = [USDC_amount, ETH_amount, 0, 0, accounts[1], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[1], "value": 1 * 10 ** 18})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == CellarPoolShareContract.balanceOf(accounts[1])

def test_reinvest(USDC, WETH, accounts, SwapRouter, CellarPoolShareContract, Contract):
    bal = CellarPoolShareContract.balanceOf(accounts[1])
    cellarRemoveParams = [bal // 3, 0, 0, accounts[1], 2 ** 256 - 1]
    USDC_balance = USDC.balanceOf(accounts[1])
    WETH_balance = WETH.balanceOf(accounts[1])
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[1]})
    USDC_diff = USDC.balanceOf(accounts[1]) - USDC_balance
    WETH_diff = WETH.balanceOf(accounts[1]) - WETH_balance
    USDC_balance = USDC.balanceOf(accounts[1])
    WETH_balance = WETH.balanceOf(accounts[1])
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[2], 2 ** 256 - 1, 10000 * 10 ** 6, 10 * 10 ** 18, 0], {"from": accounts[2], "value": 10 * 10 ** 18})
    USDC.approve(SwapRouter, 2 ** 256 - 1, {"from": accounts[2]})
    SwapRouter.exactInputSingle([USDC, WETH, 3000, accounts[2], 2 ** 256 - 1, 10000 * 10 ** 6, 1 * 10 ** 18, 0], {"from": accounts[2]})
    CellarPoolShareContract.setValidator(accounts[1], True, {"from": accounts[0]})
    CellarPoolShareContract.reinvest({"from": accounts[1]})
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[1]})
    USDC_diff_2 = USDC.balanceOf(accounts[1]) - USDC_balance
    WETH_diff_2 = WETH.balanceOf(accounts[1]) - WETH_balance
    assert USDC_diff_2 > USDC_diff or WETH_diff_2 > WETH_diff