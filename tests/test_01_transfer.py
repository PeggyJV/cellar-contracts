#!/usr/bin/python3

import pytest
import brownie

def test_transfer(accounts, CellarPoolShareContract):
    account0_balance = CellarPoolShareContract.balanceOf(accounts[0])
    account1_balance = CellarPoolShareContract.balanceOf(accounts[1])
    CellarPoolShareContract.transfer(accounts[2], account0_balance, {"from": accounts[0]})
    CellarPoolShareContract.transfer(accounts[0], account1_balance, {"from": accounts[1]})
    CellarPoolShareContract.transfer(accounts[1], account0_balance, {"from": accounts[2]})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == account1_balance
    assert CellarPoolShareContract.balanceOf(accounts[1]) == account0_balance

def test_approve(accounts, CellarPoolShareContract):
    account0_balance = CellarPoolShareContract.balanceOf(accounts[0])
    account1_balance = CellarPoolShareContract.balanceOf(accounts[1])
    with brownie.reverts():
        CellarPoolShareContract.transferFrom(accounts[1], accounts[2], account1_balance, {"from": accounts[0]})
    with brownie.reverts():
        CellarPoolShareContract.transferFrom(accounts[0], accounts[2], account0_balance, {"from": accounts[1]})
    CellarPoolShareContract.approve(accounts[1], account0_balance, {"from": accounts[0]})
    CellarPoolShareContract.transferFrom(accounts[0], accounts[2], account0_balance, {"from": accounts[1]})
    assert CellarPoolShareContract.balanceOf(accounts[2]) == account0_balance
    assert CellarPoolShareContract.balanceOf(accounts[0]) == 0
    with brownie.reverts():
        CellarPoolShareContract.transferFrom(accounts[2], accounts[0], account0_balance, {"from": accounts[1]})
    CellarPoolShareContract.approve(accounts[1], account0_balance, {"from": accounts[2]})
    CellarPoolShareContract.transferFrom(accounts[2], accounts[0], account0_balance, {"from": accounts[1]})
    assert CellarPoolShareContract.balanceOf(accounts[0]) == account0_balance