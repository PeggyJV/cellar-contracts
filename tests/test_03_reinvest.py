#!/usr/bin/python3

import pytest

def test_reinvest(USDC, WETH, accounts, SwapRouter, CellarPoolShareContract, Contract):
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    cellarRemoveParams = [bal // 3, 0, 0, accounts[0], 2 ** 256 - 1]
    USDC_balance = USDC.balanceOf(accounts[0])
    WETH_balance = WETH.balanceOf(accounts[0])
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[0]})
    USDC_diff = USDC.balanceOf(accounts[0]) - USDC_balance
    WETH_diff = WETH.balanceOf(accounts[0]) - WETH_balance
    USDC_balance = USDC.balanceOf(accounts[0])
    WETH_balance = WETH.balanceOf(accounts[0])
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[2], 2 ** 256 - 1, 10000 * 10 ** 6, 10 * 10 ** 18, 0], {"from": accounts[2], "value": 10 * 10 ** 18})
    USDC.approve(SwapRouter, 2 ** 256 - 1, {"from": accounts[2]})
    SwapRouter.exactInputSingle([USDC, WETH, 3000, accounts[2], 2 ** 256 - 1, 10000 * 10 ** 6, 1 * 10 ** 18, 0], {"from": accounts[2]})
    CellarPoolShareContract.setValidator(accounts[0], True, {"from": accounts[0]})
    CellarPoolShareContract.reinvest({"from": accounts[0]})
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[0]})
    USDC_diff_2 = USDC.balanceOf(accounts[0]) - USDC_balance
    WETH_diff_2 = WETH.balanceOf(accounts[0]) - WETH_balance
    assert USDC_diff_2 > USDC_diff or WETH_diff_2 > WETH_diff