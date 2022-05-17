const hre = require("hardhat");
const ethers = hre.ethers;
const { alchemyApiKey } = require('../secrets.json');
const { expect } = require("chai");

describe("StrategiesCellar", () => {
    let blockNumber;

    let owner;
    let alice;

    let USDC;
    let USDT;
    let DAI;
    let AAVE;

    let strategies;
    let cellarVault;

    let tx;

    let gasPrice;
    let ethPriceUSD;

    const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
    const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const aaveAddress = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9";
    const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    const aUSDCAddress = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
    const aUSDTAddress = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811";
    const aDAIAddress = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";

    const chainlinkETHUSDPriceFeedAddress = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" // Chainlink: ETH/USD Price Feed

    const curveRegistryExchangeAddress = "0x8e764bE4288B842791989DB5b8ec067279829809" // Curve Registry Exchange
    const sushiSwapRouterAddress = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F" // SushiSwap V2 Router
    const lendingPoolAddress = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"; // Aave LendingPool
    const incentivesControllerAddress = "0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5"; // StakedTokenIncentivesController
    const gravityBridgeAddress = "0x69592e6f9d21989a043646fE8225da2600e5A0f7" // Cosmos Gravity Bridge contract
    const stkAAVEAddress = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"; // StakedTokenV2Rev3

    const routerAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter

    const timetravel = async (addTime) => {
        await network.provider.send("evm_increaseTime", [addTime]);
        await network.provider.send("evm_mine");
    };

    const gasUsedLog = async (text, tx) => {
        //   console.log("tx: " + JSON.stringify(tx, null, 4))

        let block = await ethers.provider.send("eth_getBlockByNumber", [
            ethers.utils.hexValue(tx.blockNumber),
            true,
        ]);

        //   console.log("block: " + JSON.stringify(block, null, 4))

        let gasUsed = parseInt(block.gasUsed, 16);
        let txFeeUSD = (gasUsed * gasPrice * ethPriceUSD / 10**26).toFixed(2);

        console.log(
            text +
                " tx.blockNumber: " +
                tx.blockNumber +
                ", gasUsed: " +
                gasUsed + " (" +
                txFeeUSD + " USD)"
        );
    };

    const Num = (number, decimals) => {
        const [characteristic, mantissa] = number.toString().split(".");
        const padding = mantissa ? decimals - mantissa.length : decimals;
        return characteristic + (mantissa ?? "") + "0".repeat(padding);
    };

    beforeEach(async () => {
        await network.provider.request({
            method: "hardhat_reset",
            params: [
                {
                    forking: {
                        jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemyApiKey}`,
                        blockNumber: 14316384
                    },
                },
            ],
        });
        
        blockNumber = await ethers.provider.getBlockNumber();
        gasPrice = await ethers.provider.getGasPrice();

        [owner, alice] = await ethers.getSigners();

        // set 1000000 ETH to owner balance
        await network.provider.send("hardhat_setBalance", [
            owner.address,
            ethers.utils.parseEther("1000000").toHexString(),
        ]);

        // set 1000000 ETH to alice balance
        await network.provider.send("hardhat_setBalance", [
            alice.address,
            ethers.utils.parseEther("1000000").toHexString(),
        ]);

        // stablecoins contracts
        const Token = await ethers.getContractFactory(
            "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
        );
        USDC = await Token.attach(usdcAddress);
        USDT = await Token.attach(usdtAddress);
        DAI = await Token.attach(daiAddress);
        AAVE = await Token.attach(aaveAddress);
        aUSDC = await Token.attach(aUSDCAddress);

        // interface for chainlink ETH/USD price feed aggregator V3
        chainlinkETHUSDPriceFeed = await ethers.getContractAt("AggregatorInterface", chainlinkETHUSDPriceFeedAddress);
        ethPriceUSD = await chainlinkETHUSDPriceFeed.latestAnswer();

        // Uniswap V3 Router contract
        swapRouter = await ethers.getContractAt("ISwapRouter", routerAddress);
        
        await swapRouter.exactOutputSingle(
            [
                wethAddress, // tokenIn
                USDC.address, // tokenOut
                3000, // fee
                owner.address, // recipient
                1649979765, // deadline
                Num(10000000, 6), // amountOut
                ethers.utils.parseEther("50000"), // amountInMaximum
                0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
            ],
            { value: ethers.utils.parseEther("50000") }
        );

        await swapRouter.connect(alice).exactOutputSingle(
            [
                wethAddress, // tokenIn
                USDC.address, // tokenOut
                3000, // fee
                alice.address, // recipient
                1649979765, // deadline
                Num(10000000, 6), // amountOut
                ethers.utils.parseEther("50000"), // amountInMaximum
                0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
            ],
            { value: ethers.utils.parseEther("50000") }
        );

        await swapRouter.exactOutputSingle(
            [
                wethAddress, // tokenIn
                USDT.address, // tokenOut
                3000, // fee
                owner.address, // recipient
                1649979765, // deadline
                Num(10000000, 6), // amountOut
                ethers.utils.parseEther("50000"), // amountInMaximum
                0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
            ],
            { value: ethers.utils.parseEther("50000") }
        );

        await swapRouter.connect(alice).exactOutputSingle(
            [
                wethAddress, // tokenIn
                USDT.address, // tokenOut
                3000, // fee
                alice.address, // recipient
                1649979765, // deadline
                Num(10000000, 6), // amountOut
                ethers.utils.parseEther("50000"), // amountInMaximum
                0 // sqrtPriceLimitX96 - Can be used to determine limits on the pool prices which cannot  be exceeded by the swap. If you set it to 0, it's ignored.
            ],
            { value: ethers.utils.parseEther("50000") }
        );

        // Deploy cellarVault contract
        const AaveV2StablecoinCellar = await ethers.getContractFactory(
            "CellarVault"
        );

        cellarVault = await AaveV2StablecoinCellar.deploy(
            curveRegistryExchangeAddress,
            sushiSwapRouterAddress,
            lendingPoolAddress,
            incentivesControllerAddress,
            gravityBridgeAddress,
            stkAAVEAddress,
            AAVE.address,
            wethAddress
        );
        await cellarVault.deployed();

        // Deploy StrategiesCellar contract
        const StrategiesCellar = await ethers.getContractFactory(
            "StrategiesCellar"
        );

        strategies = await StrategiesCellar.deploy(
            owner.address,
            cellarVault.address
        );
        await strategies.deployed();

        await cellarVault.setStrategiesCellar(strategies.address);

        await USDC.approve(
            strategies.address,
            ethers.constants.MaxUint256
        );

        await USDC.connect(alice).approve(
            strategies.address,
            ethers.constants.MaxUint256
        );

        await USDT.approve(
            strategies.address,
            ethers.constants.MaxUint256
        );

        await USDT.connect(alice).approve(
            strategies.address,
            ethers.constants.MaxUint256
        );
    });

    describe("Add strategy", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
        });

        it("should add base strategy", async () => {
            expect((await strategies.getSubStrategiesIds(0))[0]).to.eq(undefined);
            expect((await strategies.getProportions(0))[0]).to.eq(undefined);
            expect((await strategies.getMaxProportions(0))[0]).to.eq(undefined);
            expect((await strategies.getSubStrategiesShares(0))[0]).to.eq(undefined);
            expect(await strategies.getIsBase(0)).to.eq(true);
            expect(await strategies.getBaseInactiveAsset(0)).to.eq(USDC.address);
            expect(await strategies.getBaseActiveAsset(0)).to.eq(aUSDC.address);

            expect((await strategies.getSubStrategiesIds(1))[0]).to.eq(undefined);
            expect((await strategies.getProportions(1))[0]).to.eq(undefined);
            expect((await strategies.getMaxProportions(1))[0]).to.eq(undefined);
            expect((await strategies.getSubStrategiesShares(1))[0]).to.eq(undefined);
            expect(await strategies.getIsBase(1)).to.eq(true);
            expect(await strategies.getBaseInactiveAsset(1)).to.eq(DAI.address);
            expect(await strategies.getBaseActiveAsset(1)).to.eq(aDAIAddress);
        });

        it("should add strategy", async () => {
            tx = await strategies.addStrategy(
                [0, 1],
                [90, 10],
                [100, 100]
            );
            await gasUsedLog("strategies.addStrategy", tx);

            expect((await strategies.getSubStrategiesIds(2))[0]).to.eq(0);
            expect((await strategies.getSubStrategiesIds(2))[1]).to.eq(1);
            expect((await strategies.getSubStrategiesIds(2))[2]).to.eq(undefined);

            expect((await strategies.getProportions(2))[0]).to.eq(90);
            expect((await strategies.getProportions(2))[1]).to.eq(10);

            expect((await strategies.getMaxProportions(2))[0]).to.eq(100);
            expect((await strategies.getMaxProportions(2))[1]).to.eq(100);

            expect((await strategies.getSubStrategiesShares(2))[0]).to.eq(0);
            expect((await strategies.getSubStrategiesShares(2))[1]).to.eq(0);
            expect((await strategies.getSubStrategiesShares(2))[2]).to.eq(undefined);

            expect(await strategies.getIsBase(2)).to.eq(false);
            expect(await strategies.getBaseInactiveAsset(2)).to.eq("0x0000000000000000000000000000000000000000");
            expect(await strategies.getBaseActiveAsset(2)).to.eq("0x0000000000000000000000000000000000000000");
        });

        it("should check the length of the arrays", async () => {
            await expect(strategies.addStrategy(
                [0, 1],
                [80, 10, 10],
                [100, 100]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await expect(strategies.addStrategy(
                [0, 1],
                [100],
                [100, 100]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await expect(strategies.addStrategy(
                [0, 1],
                [80, 20],
                [100, 100, 100]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await expect(strategies.addStrategy(
                [0, 1],
                [80, 20],
                [100]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await strategies.addStrategy(
                [0, 1],
                [80, 20],
                [100, 100]
            );
        });

        it("should check sum of asset allocation percentages in sub-strategies", async () => {
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await expect(strategies.addStrategy(
                [0, 1],
                [80, 30],
                [100, 100]
            )).to.be.revertedWith(
                `IncorrectPercentageSum()`
            );

            await strategies.addStrategy(
                [0, 1],
                [80, 20],
                [100, 100]
            );

            await expect(strategies.addStrategy(
                [3, 2],
                [80, 10],
                [100, 100]
            )).to.be.revertedWith(
                `IncorrectPercentageSum()`
            );

            await strategies.addStrategy(
                [3, 2],
                [90, 10],
                [100, 100]
            );
        });

        it("should be check the percentages values", async () => {
            await expect(strategies.addStrategy(
                [0, 1],
                [80, 20],
                [101, 100]
            )).to.be.revertedWith(
                `IncorrectPercentageValue()`
            );

            await strategies.addStrategy(
                [0, 1],
                [80, 20],
                [100, 100]
            );
        });

        it("should be check the sender", async () => {
            await expect(strategies.connect(alice).addBaseStrategy(USDT.address, aUSDTAddress)).to.be.revertedWith(
                `CallerNoStrategyProvider()`
            );
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await expect(strategies.connect(alice).addStrategy(
                [0, 1, 2],
                [80, 20, 0],
                [100, 100, 100]
            )).to.be.revertedWith(
                `CallerNoStrategyProvider()`
            );

            await strategies.addStrategy(
                [0, 1, 2],
                [80, 20, 0],
                [100, 100, 100]
            );
        });
    });

    describe("Update strategy", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await strategies.addStrategy(
                [0, 1, 2],
                [80, 20, 0],
                [100, 100, 100]
            );
        });

        it("should update strategy", async () => {
            expect((await strategies.getProportions(3))[0]).to.eq(80);
            expect((await strategies.getProportions(3))[1]).to.eq(20);
            expect((await strategies.getProportions(3))[2]).to.eq(0);

            await strategies.updateStrategy(
                3,
                [60, 20, 20]
            );

            expect((await strategies.getProportions(3))[0]).to.eq(60);
            expect((await strategies.getProportions(3))[1]).to.eq(20);
            expect((await strategies.getProportions(3))[2]).to.eq(20);
        });

        it("should check the length of the arrays", async () => {
            await expect(strategies.updateStrategy(
                3,
                [80, 20]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await expect(strategies.updateStrategy(
                3,
                [80, 20, 0, 0]
            )).to.be.revertedWith(
                `IncorrectArrayLength()`
            );

            await strategies.updateStrategy(
                3,
                [60, 20, 20]
            );
        });

        it("should be check the sender", async () => {
            await expect(strategies.connect(alice).updateStrategy(3, [60, 20, 20])).to.be.revertedWith(
                `CallerNoStrategyProvider()`
            );

            await strategies.updateStrategy(
                3,
                [60, 20, 20]
            );
        });
    });

    describe("Add deposite", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await strategies.addStrategy(
                [0, 1, 2],
                [80, 10, 10],
                [100, 100, 100]
            );
        });

        it("should transfer tokens to cellar vault", async () => {
            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);
            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);
            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);

            expect(await USDC.balanceOf(cellarVault.address)).to.be.closeTo(Num(23950, 6), Num(50, 6));
            expect(await USDT.balanceOf(cellarVault.address)).to.eq(0);
        });

        it("should compute inactiveBaseAssets correctly", async () => {
            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);

            expect(await strategies.inactiveBaseAssets(0)).to.eq(Num(5000, 6));

            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);

            expect(await strategies.inactiveBaseAssets(0)).to.be.closeTo(Num(12950, 6), Num(50, 6));
            expect(await strategies.inactiveBaseAssets(1)).to.be.closeTo(Num(995, 18), Num(5, 18));
            expect(await strategies.inactiveBaseAssets(2)).to.be.closeTo(Num(990, 6), Num(10, 6));

            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);

            expect(await strategies.inactiveBaseAssets(1)).to.be.closeTo(Num(1990, 18), Num(10, 18));

            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);

            expect(await strategies.inactiveBaseAssets(0)).to.be.closeTo(Num(16950, 6), Num(50, 6));
            expect(await strategies.inactiveBaseAssets(1)).to.be.closeTo(Num(2490, 18), Num(10, 18));
            expect(await strategies.inactiveBaseAssets(2)).to.be.closeTo(Num(1490, 6), Num(10, 6));

            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);

            expect(await strategies.inactiveBaseAssets(2)).to.be.closeTo(Num(2480, 6), Num(20, 6));

            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);

            expect(await strategies.inactiveBaseAssets(0)).to.be.closeTo(Num(18550, 6), Num(50, 6));
            expect(await strategies.inactiveBaseAssets(1)).to.be.closeTo(Num(2680, 18), Num(20, 18));
            expect(await strategies.inactiveBaseAssets(2)).to.be.closeTo(Num(2680, 6), Num(20, 6));
        });

        it("should compute strategiesTotalSupplies correctly", async () => {
            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);

            expect(await strategies.strategiesTotalSupplies(0)).to.be.closeTo(Num(12950, 18), Num(50, 18));
            expect(await strategies.strategiesTotalSupplies(1)).to.be.closeTo(Num(995, 18), Num(5, 18));
            expect(await strategies.strategiesTotalSupplies(2)).to.be.closeTo(Num(995, 18), Num(5, 18));
            expect(await strategies.strategiesTotalSupplies(3)).to.be.closeTo(Num(9950, 18), Num(50, 18));

            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);
            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);

            expect(await strategies.strategiesTotalSupplies(0)).to.be.closeTo(Num(16950, 18), Num(50, 18));
            expect(await strategies.strategiesTotalSupplies(1)).to.be.closeTo(Num(2495, 18), Num(5, 18));
            expect(await strategies.strategiesTotalSupplies(2)).to.be.closeTo(Num(1495, 18), Num(5, 18));
            expect(await strategies.strategiesTotalSupplies(3)).to.be.closeTo(Num(14950, 18), Num(50, 18));
            
            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);

            expect(await strategies.strategiesTotalSupplies(0)).to.be.closeTo(Num(18550, 18), Num(50, 18));
            expect(await strategies.strategiesTotalSupplies(1)).to.be.closeTo(Num(2690, 18), Num(10, 18));
            expect(await strategies.strategiesTotalSupplies(2)).to.be.closeTo(Num(2690, 18), Num(10, 18));
            expect(await strategies.strategiesTotalSupplies(3)).to.be.closeTo(Num(16950, 18), Num(50, 18));
        });

        it("should compute users balanceOf and totalSupply of strategies correctly", async () => {
            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);

            expect(await strategies.balanceOf(owner.address)).to.be.closeTo(Num(4950, 18), Num(50, 18));
            expect(await strategies.balanceOf(alice.address)).to.be.closeTo(Num(9950, 18), Num(50, 18));
            expect(await strategies.totalSupply()).to.be.closeTo(Num(14950, 18), Num(50, 18));

            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);
            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);

            expect(await strategies.balanceOf(owner.address)).to.be.closeTo(Num(10950, 18), Num(50, 18));
            expect(await strategies.balanceOf(alice.address)).to.be.closeTo(Num(9950, 18), Num(50, 18));
            expect(await strategies.totalSupply()).to.be.closeTo(Num(20950, 18), Num(50, 18));
            
            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);

            expect(await strategies.balanceOf(owner.address)).to.be.closeTo(Num(12950, 18), Num(50, 18));
            expect(await strategies.balanceOf(alice.address)).to.be.closeTo(Num(10950, 18), Num(50, 18));
            expect(await strategies.totalSupply()).to.be.closeTo(Num(23950, 18), Num(50, 18));
        });

        it("should compute subStrategiesShares correctly", async () => {
            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);

            expect((await strategies.getSubStrategiesShares(3))[0]).to.be.closeTo(Num(7950, 18), Num(50, 18));
            expect((await strategies.getSubStrategiesShares(3))[1]).to.be.closeTo(Num(995, 18), Num(5, 18));
            expect((await strategies.getSubStrategiesShares(3))[2]).to.be.closeTo(Num(995, 18), Num(5, 18));

            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);
            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);

            expect((await strategies.getSubStrategiesShares(3))[0]).to.be.closeTo(Num(11950, 18), Num(50, 18));
            expect((await strategies.getSubStrategiesShares(3))[1]).to.be.closeTo(Num(1495, 18), Num(5, 18));
            expect((await strategies.getSubStrategiesShares(3))[2]).to.be.closeTo(Num(1495, 18), Num(5, 18));

            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);

            expect((await strategies.getSubStrategiesShares(3))[0]).to.be.closeTo(Num(13550, 18), Num(50, 18));
            expect((await strategies.getSubStrategiesShares(3))[1]).to.be.closeTo(Num(1695, 18), Num(5, 18));
            expect((await strategies.getSubStrategiesShares(3))[2]).to.be.closeTo(Num(1695, 18), Num(5, 18));
        });
    });
    
    describe("enterBaseStrategy", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await strategies.addStrategy(
                [0, 1, 2],
                [80, 10, 10],
                [100, 100, 100]
            );

            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(3, USDT.address, Num(10000, 6), alice.address);
            await strategies.deposit(1, USDC.address, Num(1000, 6), owner.address);
            await strategies.deposit(3, USDT.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(2, USDC.address, Num(1000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(2000, 6), owner.address);
            
            aaveOldBalance = await USDC.balanceOf(aUSDC.address);
            await cellarVault.enterBaseStrategy(0);
        });

        it("should deposit cellar inactive assets into Aave", async () => {
            expect(await USDC.balanceOf(cellarVault.address)).to.be.closeTo(Num(5380, 6), Num(20, 6));
            expect((await USDC.balanceOf(aUSDC.address)).sub(aaveOldBalance)).to.be.closeTo(
                Num(18550, 6), Num(50, 6)
            );
        });
        
        it("should return correct amount of aTokens to cellar", async () => {
            expect(await aUSDC.balanceOf(cellarVault.address)).to.be.closeTo(
                Num(18550, 6), Num(50, 6)
            );
        });

        it("should not allow deposit if cellar does not have enough liquidity", async () => {
            await expect(cellarVault.enterBaseStrategy()).to.be.reverted;
        });

        it("should emit DepositToAave event", async () => {
            await strategies.deposit(0, USDT.address, Num(2000, 6), owner.address);

            await expect(cellarVault.enterBaseStrategy(0))
                .to.emit(cellarVault, "DepositToAave")
                .withArgs(USDC.address, Num(1986.144406, 6));
        });
    });

    describe("withdraw", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await strategies.addStrategy(
                [0, 1, 2],
                [90, 0, 10],
                [100, 100, 100]
            );

            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(1, USDC.address, Num(1000, 6), alice.address);
            await strategies.connect(alice).deposit(2, USDC.address, Num(10000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(5000, 6), owner.address);
        });

        it("should withdraw correctly when called with all inactive shares", async () => {
            let ownerOldShares = await strategies.balanceOf(owner.address);
            let ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(0, USDC.address, Num(5000, 6), owner.address, owner.address);
            let ownerNewShares = await strategies.balanceOf(owner.address);
            let ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(Num(5000, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.be.closeTo(Num(5000, 18), Num(20, 18));

            let aliceOldShares = await strategies.balanceOf(alice.address);
            let aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(1, USDC.address, Num(1000, 6), alice.address, alice.address);
            let aliceNewShares = await strategies.balanceOf(alice.address);
            let aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(1000, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(1000, 18), Num(20, 18));

            aliceOldShares = await strategies.balanceOf(alice.address);
            aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(2, USDC.address, Num(10000, 6), alice.address, alice.address);
            aliceNewShares = await strategies.balanceOf(alice.address);
            aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(10000, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(10000, 18), Num(50, 18));

            ownerOldShares = await strategies.balanceOf(owner.address);
            ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(3, USDC.address, Num(5000, 6), owner.address, owner.address);
            ownerNewShares = await strategies.balanceOf(owner.address);
            ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.eq(Num(5000, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.be.closeTo(Num(5000, 18), Num(20, 18));
        });

        it("should withdraw correctly when called with all active shares", async () => {
            // convert all inactive assets -> active assets
            await cellarVault.enterBaseStrategy(0);
            await cellarVault.enterBaseStrategy(1);
            await cellarVault.enterBaseStrategy(2);
            await timetravel(3*31*86400); // 3 month

            let ownerOldShares = await strategies.balanceOf(owner.address);
            let ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(0, USDC.address, Num(5021, 6), owner.address, owner.address);
            let ownerNewShares = await strategies.balanceOf(owner.address);
            let ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.be.closeTo(Num(5021, 6), Num(5, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.eq(Num(5000, 18));

            let aliceOldShares = await strategies.balanceOf(alice.address);
            let aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(1, USDC.address, Num(994, 6), alice.address, alice.address);
            let aliceNewShares = await strategies.balanceOf(alice.address);
            let aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.be.closeTo(Num(994, 6), Num(5, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.eq(Num(1000, 18));

            aliceOldShares = await strategies.balanceOf(alice.address);
            aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(2, USDC.address, Num(9959, 6), alice.address, alice.address);
            aliceNewShares = await strategies.balanceOf(alice.address);
            aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.be.closeTo(Num(9959, 6), Num(5, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.eq(Num(10000, 18));

            ownerOldShares = await strategies.balanceOf(owner.address);
            ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(3, USDC.address, Num(5017, 6), owner.address, owner.address);
            ownerNewShares = await strategies.balanceOf(owner.address);
            ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.be.closeTo(Num(5017, 6), Num(5, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.eq(Num(5000, 18));
        });

        it("should withdraw correctly when called with active and inactive shares", async () => {
            // convert all inactive assets -> active assets
            await cellarVault.enterBaseStrategy(0);
            await cellarVault.enterBaseStrategy(1);
            await cellarVault.enterBaseStrategy(2);

            await timetravel(3*31*86400); // 3 month

            await strategies.deposit(0, USDC.address, Num(2000, 6), owner.address);
            await strategies.connect(alice).deposit(1, USDC.address, Num(2000, 6), alice.address);
            await strategies.connect(alice).deposit(2, USDC.address, Num(2000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(3000, 6), owner.address);

            let ownerOldShares = await strategies.balanceOf(owner.address);
            let ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(0, USDC.address, Num(7021, 6), owner.address, owner.address);
            let ownerNewShares = await strategies.balanceOf(owner.address);
            let ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.be.closeTo(Num(7021, 6), Num(5, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.be.closeTo(Num(6990, 18), Num(5, 18));

            let aliceOldShares = await strategies.balanceOf(alice.address);
            let aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(1, USDC.address, Num(2994, 6), alice.address, alice.address);
            let aliceNewShares = await strategies.balanceOf(alice.address);
            let aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.be.closeTo(Num(2994, 6), Num(5, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(3015, 18), Num(5, 18));

            aliceOldShares = await strategies.balanceOf(alice.address);
            aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(2, USDC.address, Num(11959, 6), alice.address, alice.address);
            aliceNewShares = await strategies.balanceOf(alice.address);
            aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.be.closeTo(Num(11959, 6), Num(5, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(12010, 18), Num(5, 18));

            ownerOldShares = await strategies.balanceOf(owner.address);
            ownerOldBalance = await USDC.balanceOf(owner.address);
            await strategies.withdraw(3, USDC.address, Num(8017, 6), owner.address, owner.address);
            ownerNewShares = await strategies.balanceOf(owner.address);
            ownerNewBalance = await USDC.balanceOf(owner.address);
            expect(ownerNewBalance.sub(ownerOldBalance)).to.be.closeTo(Num(8017, 6), Num(5, 6));
            // expect all owner's shares to be burned
            expect(ownerOldShares.sub(ownerNewShares)).to.be.closeTo(Num(7990, 18), Num(5, 18));
        });

        it("should not allow withdraws of 0", async () => {
            await expect(
                strategies.withdraw(0, USDC.address, 0, owner.address, owner.address)
            ).to.be.revertedWith("ZeroAssets()");
        });

        it("should not allow unapproved account to withdraw using another's shares", async () => {
            // owner tries to withdraw alice's shares without approval (expect revert)
            await expect(strategies.withdraw(1, USDC.address, Num(1000, 6), owner.address, alice.address))
                .to.be.reverted;

            strategies.connect(alice).approve(Num(1000, 6).toString(), owner.address);

            // owner tries again after alice approved owner to withdraw $1 (expect pass)
            strategies.withdraw(1, USDC.address, Num(1000, 6), owner.address, alice.address);

            // owner tries to withdraw another $1 (expect revert)
            await expect(strategies.withdraw(1, USDC.address, Num(1000, 6), owner.address, alice.address))
                .to.be.reverted;
        });

        it("should only withdraw from strategy if holding pool does not contain enough funds", async () => {
            // convert all inactive assets -> active assets
            await cellarVault.enterBaseStrategy(0);
            await cellarVault.enterBaseStrategy(1);
            await cellarVault.enterBaseStrategy(2);

            await strategies.deposit(0, USDC.address, Num(2000, 6), owner.address);
            await strategies.deposit(3, USDC.address, Num(3000, 6), owner.address);

            let beforeActiveBaseAssets0 = await strategies.activeBaseAssets(0);
            let beforeInactiveBaseAssets0 = await strategies.inactiveBaseAssets(0);

            // with $125 in strategy and $125 in holding pool, should with
            await strategies.withdraw(0, USDC.address, Num(1000, 6), owner.address, owner.address);

            // active assets from strategy should not have changed
            expect(await strategies.activeBaseAssets(0)).to.be.at.least(beforeActiveBaseAssets0);
            // should have withdrawn from holding pool funds
            expect(beforeInactiveBaseAssets0.sub(await strategies.inactiveBaseAssets(0))).to.eq(Num(1000, 6));

            beforeActiveBaseAssets0 = await strategies.activeBaseAssets(0);
            beforeInactiveBaseAssets0 = await strategies.inactiveBaseAssets(0);

            let beforeActiveBaseAssets1 = await strategies.activeBaseAssets(1);
            let beforeInactiveBaseAssets1 = await strategies.inactiveBaseAssets(1);

            let beforeActiveBaseAssets2 = await strategies.activeBaseAssets(2);
            let beforeInactiveBaseAssets2 = await strategies.inactiveBaseAssets(2);

            // with $125 in strategy and $125 in holding pool, should with
            await strategies.withdraw(3, USDC.address, Num(1000, 6), owner.address, owner.address);

            // active assets from strategy should not have changed
            expect(await strategies.activeBaseAssets(0)).to.be.at.least(beforeActiveBaseAssets0);
            // should have withdrawn from holding pool funds
            expect(beforeInactiveBaseAssets0.sub(await strategies.inactiveBaseAssets(0))).to.eq(Num(900.672309, 6));

            // active assets from strategy should not have changed
            expect(await strategies.activeBaseAssets(1)).to.be.at.least(beforeActiveBaseAssets1);
            // should have withdrawn from holding pool funds
            expect(beforeInactiveBaseAssets1.sub(await strategies.inactiveBaseAssets(1))).to.eq(0);

            // active assets from strategy should not have changed
            expect(await strategies.activeBaseAssets(2)).to.be.at.least(beforeActiveBaseAssets2);
            // should have withdrawn from holding pool funds
            expect(beforeInactiveBaseAssets2.sub(await strategies.inactiveBaseAssets(2))).to.eq(Num(98.630458, 6));
        });

        it("should emit Withdraw event", async () => {
            // convert all inactive assets -> active assets
            await cellarVault.enterBaseStrategy(0);

            await timetravel(3*31*86400); // 3 month

            await expect(
                strategies.withdraw(0, USDC.address, Num(5021, 6), alice.address, owner.address)
            )
                .to.emit(strategies, "Withdraw")
                .withArgs(
                    alice.address,
                    owner.address,
                    USDC.address,
                    Num(5020.260526, 6),
                    Num(5000, 18)
                );
        });
    });
    
    describe("transfer", () => {
        beforeEach(async () => {
            await strategies.addBaseStrategy(USDC.address, aUSDC.address);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
            await strategies.addBaseStrategy(USDT.address, aUSDTAddress);

            await strategies.addStrategy(
                [0, 1, 2],
                [90, 0, 10],
                [100, 100, 100]
            );

            await strategies.deposit(0, USDC.address, Num(5000, 6), owner.address);
            await strategies.connect(alice).deposit(1, USDC.address, Num(1000, 6), alice.address);
            await strategies.connect(alice).deposit(3, USDC.address, Num(10000, 6), alice.address);
            await strategies.deposit(3, USDC.address, Num(5000, 6), owner.address);

            // convert all inactive assets -> active assets
            await cellarVault.enterBaseStrategy(0);
            await cellarVault.enterBaseStrategy(1);
        });

        it("should correctly update deposit accounting upon transferring shares", async () => {
            // transferring active shares:
            const transferredShares = Num(7000, 18);

            expect(await strategies.userStrategyShares(owner.address, 0)).to.eq(Num(5000, 18));
            expect(await strategies.userStrategyShares(owner.address, 3)).to.eq(Num(5000, 18));
            expect(await strategies.userStrategyShares(alice.address, 0)).to.eq(0);
            expect(await strategies.userStrategyShares(alice.address, 3)).to.eq(Num(10000, 18));
            
            const ownerOldBalance = await strategies.balanceOf(owner.address);
            const aliceOldBalance = await strategies.balanceOf(alice.address);
            await strategies.transfer(alice.address, transferredShares);
            const ownerNewBalance = await strategies.balanceOf(owner.address);
            const aliceNewBalance = await strategies.balanceOf(alice.address);

            expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(transferredShares);
            expect(ownerOldBalance.sub(ownerNewBalance)).to.eq(transferredShares);
            
            expect(await strategies.userStrategyShares(owner.address, 0)).to.eq(Num(0, 18));
            expect(await strategies.userStrategyShares(owner.address, 3)).to.eq(Num(3000, 18));
            expect(await strategies.userStrategyShares(alice.address, 0)).to.eq(Num(5000, 18));
            expect(await strategies.userStrategyShares(alice.address, 3)).to.eq(Num(12000, 18));
        });

        it("should correctly withdraw transferred shares", async () => {
            // transferring active shares:
            const transferredShares = Num(7000, 18);

            await strategies.transfer(alice.address, transferredShares);

            let aliceOldShares = await strategies.balanceOf(alice.address);
            let aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(0, USDC.address, Num(5000, 6), alice.address, alice.address);
            let aliceNewShares = await strategies.balanceOf(alice.address);
            let aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(5000, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(5000, 18), Num(20, 18));

            aliceOldShares = await strategies.balanceOf(alice.address);
            aliceOldBalance = await USDC.balanceOf(alice.address);
            await strategies.connect(alice).withdraw(3, USDC.address, Num(11000, 6), alice.address, alice.address);
            aliceNewShares = await strategies.balanceOf(alice.address);
            aliceNewBalance = await USDC.balanceOf(alice.address);
            expect(aliceNewBalance.sub(aliceOldBalance)).to.eq(Num(11000, 6));
            // expect all alice's shares to be burned
            expect(aliceOldShares.sub(aliceNewShares)).to.be.closeTo(Num(11000, 18), Num(50, 18));
        });
        
        it("should require approval for transferring other's shares", async () => {
            await strategies.approve(alice.address, Num(6000, 18));

            await strategies
                .connect(alice)
                ["transferFrom(address,address,uint256)"](
                    owner.address,
                    alice.address,
                    Num(5000, 18)
                );

            await expect(
                strategies["transferFrom(address,address,uint256)"](
                    alice.address,
                    owner.address,
                    Num(1000, 18)
                )
            ).to.be.reverted;
        });
    });
});
