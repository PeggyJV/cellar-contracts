from brownie import CellarPoolShareLimitUSDCETH, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "Cellar Pool Share Limited USDC-ETH-3000"
    symbol = "CPS"
    token0 = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    token1 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    cellarTickInfo = [[0,210000,180000,1]]
    CellarPoolShareLimitUSDCETH.deploy(name, symbol, token0, token1, 3000, cellarTickInfo, {"from":acct})