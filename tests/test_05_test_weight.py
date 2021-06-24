#!/usr/bin/python3

import pytest

def test_weight(USDC, WETH, accounts, SwapRouter, NonfungiblePositionManager, CellarPoolShareContract):
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[0], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[0], "value": 6 * 10 ** 18})
    USDC.approve(CellarPoolShareContract, 6000 * 10 ** 6, {"from": accounts[0]})
    USDC_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [1000 * 10 ** 6, 1 * 10 ** 18, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    cellarAddParams = [5000 * 10 ** 6, 1 * 10 ** 18, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})

    token_id_0 = NonfungiblePositionManager.tokenOfOwnerByIndex(CellarPoolShareContract, 0) # weight 1
    token_id_1 = NonfungiblePositionManager.tokenOfOwnerByIndex(CellarPoolShareContract, 1) # weight 5
    token_id_2 = NonfungiblePositionManager.tokenOfOwnerByIndex(CellarPoolShareContract, 2) # weight 2

    liq0 = NonfungiblePositionManager.positions(token_id_0)[7]
    liq1 = NonfungiblePositionManager.positions(token_id_1)[7]
    liq2 = NonfungiblePositionManager.positions(token_id_2)[7]

    print(liq0 * 5)
    print(liq1)

    print(liq0 * 2)
    print(liq2)