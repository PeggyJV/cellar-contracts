from brownie import CellarPoolShare, accounts

def main():
    name = "Cellar Pool Share Token"
    symbol = "CPS"
    token0 = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    token1 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    cellarTickInfo = [[0, 240000, 210000, 1], [0, 210000, 180000, 5], [0, 180000, 150000, 2]]
    CellarPoolShare.deploy(name, symbol, token0, token1, 3000, cellarTickInfo, {'from':accounts[0]})