#!/usr/bin/python3

import pytest
import math

def test_main(USDC, DAI, WETH, accounts, NonfungiblePositionManager, UniswapV2Router02, CellarPoolShareContract, Contract):
    UniswapV2Router02.swapETHForExactTokens(10000 * 10 ** 18, [WETH, DAI], accounts[0], 2 ** 256 - 1, {"from": accounts[0], "value": 10 * 10 ** 18})
    DAI.approve(CellarPoolShareContract, 10000 * 10 ** 18, {"from": accounts[0]})
    cellarAddParams = [10000 * 10 ** 18, 7 * 10 ** 18, 0, 0, accounts[0], 2 ** 256 - 1]
    print(DAI.balanceOf(accounts[0]))
    print(accounts[0].balance())
    print(DAI.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 7 * 10 ** 18})
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    print(DAI.balanceOf(accounts[0]))
    print(accounts[0].balance())
    print(DAI.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    print(bal)
    cellarRemoveParams = [bal // 2, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.removeLiquidityEthFromUniV3(cellarRemoveParams, {"from": accounts[0]})
    print(DAI.balanceOf(accounts[0]))
    print(accounts[0].balance())
    print(DAI.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    print(CellarPoolShareContract.balanceOf(accounts[0]))
    CellarPoolShareContract.removeLiquidityEthFromUniV3(cellarRemoveParams, {"from": accounts[0]})
    print(DAI.balanceOf(accounts[0]))
    print(accounts[0].balance())
    print(DAI.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    print(CellarPoolShareContract.balanceOf(accounts[0]))