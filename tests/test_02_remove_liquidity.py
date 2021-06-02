#!/usr/bin/python3

import pytest

def test_remove_liquidity(USDC, WETH, accounts, CellarPoolShareContract):
    bal = CellarPoolShareContract.balanceOf(accounts[1])
    cellarRemoveParams = [bal // 3, 0, 0, accounts[1], 2 ** 256 - 1]
    CellarPoolShareContract.removeLiquidityFromUniV3(cellarRemoveParams, {"from": accounts[1]})
    assert bal - CellarPoolShareContract.balanceOf(accounts[1]) == bal // 3

def test_remove_liquidity_ETH(USDC, WETH, accounts, CellarPoolShareContract):
    bal = CellarPoolShareContract.balanceOf(accounts[1])
    cellarRemoveParams = [bal // 2, 0, 0, accounts[1], 2 ** 256 - 1]
    CellarPoolShareContract.removeLiquidityEthFromUniV3(cellarRemoveParams, {"from": accounts[1]})
    assert bal - CellarPoolShareContract.balanceOf(accounts[1]) == bal // 2
