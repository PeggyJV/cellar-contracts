#!/usr/bin/python3

import pytest

def test_rebalance(USDC, WETH, accounts, CellarPoolShareContract, Contract):
    cellarRebalanceParams = [[0, 240000, 210000, 1], [0, 210000, 180000, 5], [0, 180000, 150000, 2]]
    bal = CellarPoolShareContract.balanceOf(accounts[0])
    print(USDC.balanceOf(CellarPoolShareContract))
    print(WETH.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    CellarPoolShareContract.rebalance(cellarRebalanceParams)
    assert bal == CellarPoolShareContract.balanceOf(accounts[0])
    print(USDC.balanceOf(CellarPoolShareContract))
    print(WETH.balanceOf(CellarPoolShareContract))
    print(CellarPoolShareContract.balance())
    