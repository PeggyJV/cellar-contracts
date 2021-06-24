#!/usr/bin/python3

import pytest

def test_weight(USDC, WETH, accounts, SwapRouter, NonfungiblePositionManager, CellarPoolShareContract):
    ACCURACY = 10 ** 6
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[0], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[0], "value": 6 * 10 ** 18})
    USDC.approve(CellarPoolShareContract, 6000 * 10 ** 6, {"from": accounts[0]})
    USDC_amount = 1000 * 10 ** 6
    ETH_amount = 1 * 10 ** 18
    cellarAddParams = [1000 * 10 ** 6, 1 * 10 ** 18, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})
    cellarAddParams = [5000 * 10 ** 6, 1 * 10 ** 18, 0, 0, accounts[0], 2 ** 256 - 1]
    CellarPoolShareContract.addLiquidityEthForUniV3(cellarAddParams, {"from": accounts[0], "value": 1 * 10 ** 18})

    token_id_0 = NonfungiblePositionManager.tokenOfOwnerByIndex(CellarPoolShareContract, 0)
    liq_0 = NonfungiblePositionManager.positions(token_id_0)[7]
    weight_0 = CellarPoolShareContract.cellarTickInfo(0)[3]
    NFT_count = NonfungiblePositionManager.balanceOf(CellarPoolShareContract)
    for i in range(NFT_count - 1):
        token_id = NonfungiblePositionManager.tokenOfOwnerByIndex(CellarPoolShareContract, i + 1)
        liq = NonfungiblePositionManager.positions(token_id)[7]
        weight = CellarPoolShareContract.cellarTickInfo(i + 1)[3]
        assert approximateCompare(liq_0 * weight, liq * weight_0, ACCURACY)

def approximateCompare(a, b, accuracy):
    delta = 0
    if a > b:
        return (a - b) * accuracy < a
    else:
        return (b - a) * accuracy < b
    