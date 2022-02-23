from brownie import AaveStablecoinCellar, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "Aave Stablecoin Cellar Inactive LP Token"
    symbol = "ASCCT"

    AaveStablecoinCellar.deploy(name, symbol, {"from":acct})
