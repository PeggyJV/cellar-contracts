from brownie import CellarPoolShare, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "Cellar Pool Share Test ETH USDT"
    symbol = "CPST"
    token0 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
    token1 = "0xdac17f958d2ee523a2206206994597c13d831ec7"
    cellarTickInfo = [[0,-198240,-198540,2],[0,-198720,-199080,7],[0,-199260,-199620,14],[0,-199860,-200220,14],[0,-200460,-200880,7],[0,-201120,-201540,2]]
    CellarPoolShare.deploy(name, symbol, token0, token1, 3000, cellarTickInfo, {"from":acct})