from brownie import Cellar, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "Cellar Inactive LP Token"
    symbol = "CILPT"

    Cellar.deploy(name, symbol, {"from":acct})
