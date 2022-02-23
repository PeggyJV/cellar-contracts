#!/usr/bin/python3

import pytest
import brownie

def test_initial_state(accounts, ASCCellarContract):
    assert ASCCellarContract.name() == "Aave Stablecoin Cellar Inactive LP Token"
    assert ASCCellarContract.symbol() == "ASCCT"
    assert ASCCellarContract.decimals() == 18
    assert ASCCellarContract.owner() == accounts[1]
    assert ASCCellarContract.balanceOf(accounts[1]) == 0
    assert ASCCellarContract.totalSupply() == 0
    
    with brownie.reverts():
        ASCCellarContract.input_tokens_list(0)
        
def test_init_input_token(USDT, USDC, accounts, ASCCellarContract):
    ASCCellarContract.initInputToken(USDT, {"from": accounts[1]})
    assert ASCCellarContract.input_tokens_list(0) == USDT.address
    
    with brownie.reverts():
        ASCCellarContract.input_tokens_list(1)
        
    ASCCellarContract.initInputToken(USDC, {"from": accounts[1]})
    assert ASCCellarContract.input_tokens_list(1) == USDC.address

def test_add_liquidity(WETH, USDT, USDC, accounts, SwapRouter, ASCCellarContract):
    SwapRouter.exactOutputSingle([WETH, USDT, 3000, accounts[1], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[1], "value": 6 * 10 ** 18})
    SwapRouter.exactOutputSingle([WETH, USDC, 3000, accounts[1], 2 ** 256 - 1, 6000 * 10 ** 6, 6 * 10 ** 18, 0], {"from": accounts[1], "value": 6 * 10 ** 18})
    
    USDT.approve(ASCCellarContract, 100 * 10 ** 6, {"from": accounts[1]})
    ASCCellarContract.addLiquidity(USDT, 100 * 10 ** 6, {"from": accounts[1]})
    
    USDC.approve(ASCCellarContract, 100 * 10 ** 6, {"from": accounts[1]})
    ASCCellarContract.addLiquidity(USDC, 100 * 10 ** 6, {"from": accounts[1]})
    
    assert ASCCellarContract.totalSupply() == 200 * 10 ** 6
    assert ASCCellarContract.balanceOf(accounts[1]) == 200 * 10 ** 6
    assert USDT.balanceOf(ASCCellarContract) == 100 * 10 ** 6
    assert USDC.balanceOf(ASCCellarContract) == 100 * 10 ** 6

def test_swap(WETH, USDT, USDC, accounts, ASCCellarContract):
    usdtBalanceBefore = USDT.balanceOf(ASCCellarContract)
    usdcBalanceBefore = USDC.balanceOf(ASCCellarContract)
    amountIn = 20 * 10 ** 6
    ASCCellarContract.swap(USDT, USDC, amountIn, 0, {"from": accounts[1]})
    assert USDT.balanceOf(ASCCellarContract) == usdtBalanceBefore - amountIn
    assert USDC.balanceOf(ASCCellarContract) > usdcBalanceBefore

def test_multihop_swap(WETH, USDT, USDC, accounts, ASCCellarContract):
    usdtBalanceBefore = USDT.balanceOf(ASCCellarContract)
    usdcBalanceBefore = USDC.balanceOf(ASCCellarContract)
    amountIn = 20 * 10 ** 6
    ASCCellarContract.multihopSwap([USDT, WETH, USDC], amountIn, 0, {"from": accounts[1]})
    assert USDT.balanceOf(ASCCellarContract) == usdtBalanceBefore - amountIn
    assert USDC.balanceOf(ASCCellarContract) > usdcBalanceBefore

def test_enter_strategy(USDT, USDC, accounts, LendingPool, ASCCellarContract):
    amount = 40 * 10 ** 6
  
    usdtBalanceBefore = USDT.balanceOf(ASCCellarContract)
    usdtAaveDepositBalancesBefore = ASCCellarContract.aaveDepositBalances(USDT)
    
    ASCCellarContract.enterStrategy(USDT, amount, {"from": accounts[1]})
    
    assert USDT.balanceOf(ASCCellarContract) == usdtBalanceBefore - amount
    assert ASCCellarContract.aaveDepositBalances(USDT) == usdtAaveDepositBalancesBefore + amount
    
    usdcBalanceBefore = USDC.balanceOf(ASCCellarContract)
    usdcAaveDepositBalancesBefore = ASCCellarContract.aaveDepositBalances(USDC)
    
    ASCCellarContract.enterStrategy(USDC, amount, {"from": accounts[1]})
    
    assert USDC.balanceOf(ASCCellarContract) == usdcBalanceBefore - amount
    assert ASCCellarContract.aaveDepositBalances(USDC) == usdcAaveDepositBalancesBefore + amount

def test_redeem_from_aave(USDT, USDC, accounts, LendingPool, ASCCellarContract):
    amount = 20 * 10 ** 6
  
    usdtBalanceBefore = USDT.balanceOf(ASCCellarContract)
    usdtAaveDepositBalancesBefore = ASCCellarContract.aaveDepositBalances(USDT)
    
    ASCCellarContract.redeemFromAave(USDT, amount, {"from": accounts[1]})
    
    assert USDT.balanceOf(ASCCellarContract) == usdtBalanceBefore + amount
    assert ASCCellarContract.aaveDepositBalances(USDT) == usdtAaveDepositBalancesBefore - amount
    
    usdcBalanceBefore = USDC.balanceOf(ASCCellarContract)
    usdcAaveDepositBalancesBefore = ASCCellarContract.aaveDepositBalances(USDC)
    
    ASCCellarContract.redeemFromAave(USDC, amount, {"from": accounts[1]})
    
    assert USDC.balanceOf(ASCCellarContract) == usdcBalanceBefore + amount
    assert ASCCellarContract.aaveDepositBalances(USDC) == usdcAaveDepositBalancesBefore - amount
