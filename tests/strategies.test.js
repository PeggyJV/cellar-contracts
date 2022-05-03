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
    let cellar;

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

        // Deploy cellar contract
        const AaveV2StablecoinCellar = await ethers.getContractFactory(
            "AaveV2StablecoinCellar"
        );

        cellar = await AaveV2StablecoinCellar.deploy(
            USDC.address,
            curveRegistryExchangeAddress,
            sushiSwapRouterAddress,
            lendingPoolAddress,
            incentivesControllerAddress,
            gravityBridgeAddress,
            stkAAVEAddress,
            AAVE.address,
            wethAddress
        );
        await cellar.deployed();

        // Deploy StrategiesCellar contract
        const StrategiesCellar = await ethers.getContractFactory(
            "StrategiesCellar"
        );

        strategies = await StrategiesCellar.deploy(
            owner.address,
            cellar.address
        );
        await strategies.deployed();

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
            await strategies.addBaseStrategy(USDC.address, aUSDCAddress);
            await strategies.addBaseStrategy(DAI.address, aDAIAddress);
        });

        it("should add base strategy", async () => {
            expect((await strategies.getSubStrategyIds(0))[0]).to.eq(undefined);
            expect((await strategies.getProportions(0))[0]).to.eq(undefined);
            expect((await strategies.getMaxProportions(0))[0]).to.eq(undefined);
            expect((await strategies.getSubStrategyShares(0))[0]).to.eq(undefined);
            expect(await strategies.getIsBase(0)).to.eq(true);
            expect(await strategies.getBaseInactiveAsset(0)).to.eq(USDC.address);
            expect(await strategies.getBaseActiveAsset(0)).to.eq(aUSDCAddress);

            expect((await strategies.getSubStrategyIds(1))[0]).to.eq(undefined);
            expect((await strategies.getProportions(1))[0]).to.eq(undefined);
            expect((await strategies.getMaxProportions(1))[0]).to.eq(undefined);
            expect((await strategies.getSubStrategyShares(1))[0]).to.eq(undefined);
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

            expect((await strategies.getSubStrategyIds(2))[0]).to.eq(0);
            expect((await strategies.getSubStrategyIds(2))[1]).to.eq(1);
            expect((await strategies.getSubStrategyIds(2))[2]).to.eq(undefined);

            expect((await strategies.getProportions(2))[0]).to.eq(90);
            expect((await strategies.getProportions(2))[1]).to.eq(10);

            expect((await strategies.getMaxProportions(2))[0]).to.eq(100);
            expect((await strategies.getMaxProportions(2))[1]).to.eq(100);

            expect((await strategies.getSubStrategyShares(2))[0]).to.eq(0);
            expect((await strategies.getSubStrategyShares(2))[1]).to.eq(0);
            expect((await strategies.getSubStrategyShares(2))[2]).to.eq(undefined);

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
            await strategies.addBaseStrategy(USDC.address, aUSDCAddress);
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
            await strategies.addBaseStrategy(USDC.address, aUSDCAddress);
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

            expect(await USDC.balanceOf(cellar.address)).to.eq(Num(9000, 6));
            expect(await USDT.balanceOf(cellar.address)).to.eq(Num(15000, 6));
        });
    });
});